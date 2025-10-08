#!/bin/sh

set -euo pipefail
set -x

echo "Starting MITM proxy for verifier attestation traffic..."

# Listen on 9002 for verifier, forward to agent:9002
# - Inbound (from verifier): Use attacker cert, no verification
# - Outbound (to agent): Use Keylime client cert, verify CA but NOT hostname
exec socat -d -d -v \
  OPENSSL-LISTEN:9002,fork,reuseaddr,cert=/etc/attacker_certs/mitm_server.crt,key=/etc/attacker_certs/mitm_server.key,verify=0 \
  OPENSSL:keylime-agent:9002,cert=/var/lib/keylime/cv_ca/client-cert.crt,key=/var/lib/keylime/cv_ca/client-private.pem,cafile=/var/lib/keylime/cv_ca/cacert.crt,verify=1,commonname=""