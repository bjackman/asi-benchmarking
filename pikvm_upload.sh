#!/bin/bash

set -eux

# Disconnect MSD
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/set_connected?connected=0"
# Delete existing image.
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/remove?image=image.raw"
# Compress image and upload it.
# --http1.1: https://stackoverflow.com/questions/56413290/getting-curl-92-http-2-stream-1-was-not-closed-cleanly-internal-error-err
gzip --stdout image.raw |  curl -v -X POST --data-binary @- -H 'Content-Encoding: gzip'  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/write?image=image.raw" --http1.1
# Select image for MSD
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/set_params?image=image.raw&cdrom=0"
# Reconnect MSD
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/set_connected?connected=1"