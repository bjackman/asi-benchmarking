#!/bin/bash

set -eux

# Disconnect MSD
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/set_connected?connected=0"
# Delete existing image.
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/remove?image=image.raw"
# Compress image and upload it.
gzip --stdout image.raw |  curl -v -X POST --data-binary @- -H 'Content-Encoding: gzip'  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/write?image=image.raw"
# Select image & params for MSD.
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/set_params?image=image.raw&cdrom=0&rw=1"
# Reconnect MSD
curl -v -X POST  -k -H X-KVMD-User:admin -H X-KVMD-Passwd:$PASSWORD "https://34.90.180.154:8080/api/msd/set_connected?connected=1"