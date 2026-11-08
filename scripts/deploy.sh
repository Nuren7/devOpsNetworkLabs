#!/usr/bin/env sh
set -eu

: "${DEPLOY_HOST:?Set DEPLOY_HOST to user@your-linux-host}"
: "${DEPLOY_PATH:?Set DEPLOY_PATH to the project directory on the host}"
: "${SSH_KEY_PATH:?Set SSH_KEY_PATH to your private ED25519 key}"

if [ ! -f "$SSH_KEY_PATH" ]; then
  printf 'SSH private key not found: %s\n' "$SSH_KEY_PATH" >&2
  exit 1
fi

ssh -i "$SSH_KEY_PATH" \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes \
  "$DEPLOY_HOST" \
  "cd '$DEPLOY_PATH' && docker compose up -d --build"
