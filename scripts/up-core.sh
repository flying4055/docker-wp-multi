#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/lib/compose.sh"

if [[ ! -f docker/.env ]]; then
  echo "[error] missing docker/.env, run: cp docker/.env.example docker/.env"
  exit 1
fi

init_compose_cmd

./scripts/init-network.sh

compose_cmd --env-file docker/.env -f docker/mariadb/docker-compose.yml up -d
compose_cmd --env-file docker/.env -f docker/redis/docker-compose.yml up -d

echo "[ok] core services started: mariadb + redis"
