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

host_ssh_visible() {
    nc -zw5 "$HOST" $HOST_SSH_PORT
}

# Shut down host so it doesn't leak proxy connections, unless it seems to be off already.
if [[ $(curl_pikvm GET /api/atx | jq ".result.leds.power") != "false" ]]; then
    if host_ssh_visible; then
        ansible-playbook -i host-inventory.yaml host-shutdown.yaml || echo "shutdown failed, continuing"
    fi

    # Kill the power. It's pretty likely it's still shutting down (or shutdown
    # failed), but that's fine since we're about to totally replace the disk
    # anyway.  The main reason we shut it down was to kill the SSH tunneling
    # service which is probably done by now.
    # For some reason I found /api/atx/power?action=off doesn't do anything at least for my HW.
    curl_pikvm POST "/api/atx/click?button=power&wait=1"
fi

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

# Boot 'er up
curl_pikvm POST "/api/atx/power?action=on"
# Wait until the SSH port becomes visible.
# -z = scan only,  -w5 = 5s timeout
deadline_s=$(($(date +%s) + 120))
while ! host_ssh_visible; do
    current_time_s=$(date +%s)
    if (( current_time_s > deadline_s )); then
        echo "Timed out after 2m waiting for host SSH port to appear"
        exit 1
    fi
    sleep 1
done

# Run the benchmark
ansible-playbook -i host-inventory.yaml host-setup.yaml
# ... On bare metal
ansible-playbook -i host-inventory.yaml host-pts.yaml
# ... In the guest
ansible-playbook -i guest-inventories/aethelred/tmp/guest-inventory.yaml guest-pts.yaml
./upload_results.sh "$DB_ROOT"