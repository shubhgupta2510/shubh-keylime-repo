#!/bin/sh

# Wait for agent to be ready
sleep 5

echo "Starting Agent MITM proxy (HTTPS-to-HTTP)..."
# This will accept HTTPS connections from verifier on port 9002
# and forward them as HTTP to the agent on port 9002 (internal)
# Using legitimate server cert to avoid detection
exec socat -d -d -v \
    OPENSSL-LISTEN:9002,fork,reuseaddr,cert=/etc/attacker_certs/server-cert.crt,key=/etc/attacker_certs/server-private.pem,verify=0 \
    TCP:keylime-agent:9002