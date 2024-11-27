#!/bin/bash

# The everything script! Sets up hosts and guests, runs the benchmark, uploads
# the results.
# Arg is the root of the results database

set -eux
set -o pipefail

DB_ROOT="$1"

# First arg is verb, second arg is query.
curl_pikvm() {
    curl -X "$1"  -k -H X-KVMD-User:${PIKVM_USER:-admin} -H X-KVMD-Passwd:$PIKVM_PASSWORD \
        "https://${PIKVM_HOST}:${PIKVM_HTTPS_PORT:-443}/$2" 2>/dev/null
}

ssh_pikvm() {
    ssh -p "$PIKVM_SSH_PORT" "$PIKVM_SSH_USER@$PIKVM_HOST" "$@"
}

# Shut down host so it doesn't leak proxy connections, unless it seems to be off already.
if [[ $(curl_pikvm GET /api/atx | jq ".result.leds.power") != "false" ]]; then
    ansible-playbook -i host-inventory.yaml host-shutdown.yaml
fi
# Kill the power. It's pretty likely it's still shutting down (or shutdown
# failed), but that's fine since we're about to totally replace the disk anyway.
# The main reason we shut it down was to kill the SSH tunneling service which is
# probably done by now.
curl_pikvm POST "/api/atx/power?action=on"

# Disconnect mass storage, so we can write it.
curl_pikvm POST "/api/msd/set_connected?connected=0"

# Upload image. We need to do this using rsync because the HTTP upload can't
# handle sparse images properly.
# https://docs.pikvm.org/msd/#manual-drives-management
ssh_pikvm kvmd-helper-otgmsd-remount rw
# Dont use -a since we care about the permissions on the remote. But set --times
# so rsync can detect when no new copying is needed.
rsync -vz --sparse --progress --times -e "ssh -p $PIKVM_SSH_PORT" \
    mkosi/image.raw "$PIKVM_SSH_USER@$PIKVM_HOST:/var/lib/kvmd/msd/image.raw"
# Not documented but PiKVM falls over without at least these perms:
ssh_pikvm chown kvmd:kvmd /var/lib/kvmd/msd/image.raw
ssh_pikvm chmod 0644 /var/lib/kvmd/msd/image.raw
ssh_pikvm kvmd-helper-otgmsd-remount ro

# Reconnect MSD using image we just uploaded.
curl_pikvm POST "/api/msd/set_params?image=image.raw&cdrom=0&rw=1"
curl_pikvm POST "/api/msd/set_connected?connected=1"

# Boot 'er up
curl_pikvm POST "/api/atx/power?action=on"

# Run the benchmark
ansible-playbook -i host-inventory.yaml host-setup.yaml
ansible-playbook -i guest-inventories/ibpb/tmp/guest-inventory.yaml guest-setup.yaml
./upload_results.sh "$DB_ROOT"