#!/bin/bash
set -euo pipefail

CERT_DIR=/tmp/attacker_ca
mkdir -p "$CERT_DIR"

# Generate CA key
openssl genrsa -out "$CERT_DIR/attacker_ca.key" 2048

# Generate CA cert with proper extensions
openssl req -new -x509 -days 365 -key "$CERT_DIR/attacker_ca.key" \
  -out "$CERT_DIR/attacker_ca.crt" \
  -subj "/CN=Attacker CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# Generate MITM server key
openssl genrsa -out "$CERT_DIR/mitm_server.key" 2048

# Create CSR for mitm-verifier
openssl req -new -key "$CERT_DIR/mitm_server.key" \
  -out "$CERT_DIR/mitm_server.csr" \
  -subj "/CN=mitm-verifier"

# Sign server cert with SAN
openssl x509 -req -in "$CERT_DIR/mitm_server.csr" \
  -CA "$CERT_DIR/attacker_ca.crt" -CAkey "$CERT_DIR/attacker_ca.key" -CAcreateserial \
  -out "$CERT_DIR/mitm_server.crt" -days 365 \
  -extfile <(echo "subjectAltName=DNS:mitm-verifier")

# Verify
echo "=== Attacker CA ==="
openssl x509 -in "$CERT_DIR/attacker_ca.crt" -noout -text | grep -A3 "Key Usage"
echo "=== MITM Server ==="
openssl x509 -in "$CERT_DIR/mitm_server.crt" -noout -text | grep -A1 "Subject Alternative Name"