#!/bin/sh

# This script will be run inside the mitm container.
# It executes the socat command with the correct arguments.

set -e

# Enable debugging to see what's happening
set -x

echo "Starting socat proxy..."

# Print the arguments we're about to pass to socat
echo "First argument: OPENSSL-LISTEN:8890,fork,reuseaddr,cert=/etc/attacker_certs/mitm_server.crt,key=/etc/attacker_certs/mitm_server.key,verify=0"
echo "Second argument: OPENSSL:keylime-registrar:8890,cert=/etc/attacker_certs/mitm_client.crt,key=/etc/attacker_certs/mitm_client.key"

# Execute socat with explicit argument separation
exec socat -d -d \
  TCP-LISTEN:8890,fork,reuseaddr \
  TCP:keylime-registrar:8890