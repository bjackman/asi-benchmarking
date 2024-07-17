#!/bin/bash

# The everything script! Sets up hosts and guests, runs the benchmark, uploads
# the results.
# Arg is the root of the results database

set -eux
set -o pipefail

DB_ROOT="$1"

# Disable all mitigations except retbleed. Can't use mitigations=off because
# then it's impossible to enable retbleed mitigations. Include mitigations=auto
# in case there's a mitigations=off prepended by something (like
# CONFIG_CMDLINE).
MITIGATIONS_OFF="mitigations=auto gather_data_sampling=off kvm.nx_huge_pages=off l1tf=off mds=off \
    mmio_stale_data=off nopti nospectre_v1 nospectre_v2 reg_file_data_sampling=off \
    spec_rstack_overflow=off spectre_bhi=off spectre_v2_user=off srbds=off \
    tsx_async_abort=off"

ansible-playbook -i host-inventory.yaml host-setup.yaml \
    -e "kernel_cmdline=\"$MITIGATIONS_OFF retbleed=ibpb\""
ansible-playbook $(printf -- ' -i %s'  guest-inventories/**/tmp/*.yaml) guest-setup.yaml
./upload_results.sh "$DB_ROOT"

ansible-playbook -i host-inventory.yaml host-setup.yaml \
    -e "kernel_cmdline=\"$MITIGATIONS_OFF retbleed=off asi=on\""
ansible-playbook $(printf -- ' -i %s'  guest-inventories/**/tmp/*.yaml) guest-setup.yaml
./upload_results.sh "$DB_ROOT"

ansible-playbook -i host-inventory.yaml host-setup.yaml \
    -e "kernel_cmdline=\"$MITIGATIONS_OFF retbleed=off\""
ansible-playbook $(printf -- ' -i %s'  guest-inventories/**/tmp/*.yaml) guest-setup.yaml
./upload_results.sh "$DB_ROOT"

ansible-playbook -i host-inventory.yaml host-setup.yaml \
    -e "kernel_cmdline=\"$MITIGATIONS_OFF retbleed=unret\""
ansible-playbook $(printf -- ' -i %s'  guest-inventories/**/tmp/*.yaml) guest-setup.yaml
./upload_results.sh "$DB_ROOT"