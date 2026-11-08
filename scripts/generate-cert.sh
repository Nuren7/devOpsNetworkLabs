#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CERT_DIR="$ROOT_DIR/nginx/certs"

mkdir -p "$CERT_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_DIR/server.key" \
  -out "$CERT_DIR/server.crt" \
  -subj "/CN=myapp.local" \
  -addext "subjectAltName=DNS:myapp.local,DNS:localhost,IP:127.0.0.1"
chmod 600 "$CERT_DIR/server.key"

printf 'Created a self-signed certificate in %s\n' "$CERT_DIR"
