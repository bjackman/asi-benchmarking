#!/bin/bash

# Dumps results in the output directory specified by the argument.
# Uses Brendan's special results database format.
# That means it hashes the result inputs to check if they've already been
# uploaded, so this should be idempotent.

set -eux
set -o pipefail

DB_ROOT="$1"

RESULT_ID_PREFIX=asi-benchmarking-pts

# These are hard-coded in the Ansible scripts
JSON_PTS_RESULTS_DIR="json-pts-results"
HOST_ARTIFACTS_DIR="host_artifacts"
GUEST_ARTIFACTS_DIR="guest_artifacts"

for guest_artifacts_dir in "$GUEST_ARTIFACTS_DIR"/*; do
    json_path="$guest_artifacts_dir"/pts-results.json
    # sha256sum spits out the sum and the filename. The awk bit takes the first
    # 12 chars of the sum.
    result_id="$RESULT_ID_PREFIX:$(sha256sum "$json_path" | awk '{ print substr($1, 1, 12) }')"

    # Already present?
    result_path="$DB_ROOT/$result_id"
    if [[ -e "$result_path" ]]; then
        echo "$result_path already exists, skipping upload" >2
        continue
    fi

    # Don't use mkdir -p to avoid accidentally creating rando directories.
    mkdir "$result_path"
    artifacts_path=$result_path/artifacts
    mkdir "$artifacts_path"

    cp -R "$guest_artifacts_dir" "$artifacts_path"
    ansible_host="$(basename "$guest_artifacts_dir" | sed 's/_vm[0-9]*$//')"
    cp -R "$HOST_ARTIFACTS_DIR/$ansible_host" "$artifacts_path"
done