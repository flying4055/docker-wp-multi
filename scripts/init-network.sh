#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ -f docker/.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source docker/.env
  set +a
fi

NETWORK_NAME="${WORDPRESS_NETWORK:-wordpress-network}"

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "[ok] docker network exists: $NETWORK_NAME"
else
  docker network create "$NETWORK_NAME" >/dev/null
  echo "[ok] docker network created: $NETWORK_NAME"
fi
