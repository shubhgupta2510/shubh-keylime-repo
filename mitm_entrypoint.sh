#!/bin/sh

# This script will be run inside the mitm container.
# It executes the socat command with the correct arguments.

set -euo pipefail

# Enable debugging to see what's happening
set -x

echo "Starting socat proxy..."

# Terminate TLS from agent, re-send cleartext to registrar
# -v -x cause socat to dump payloads in hex/ASCII in the logs
exec socat -d -d -v \
  OPENSSL-LISTEN:8891,fork,reuseaddr,cert=/etc/attacker_certs/mitm_server.crt,key=/etc/attacker_certs/mitm_server.key,verify=0 \
  OPENSSL:keylime-registrar:8891,cert=/etc/attacker_certs/mitm_client.crt,key=/etc/attacker_certs/mitm_client.key,verify=0
