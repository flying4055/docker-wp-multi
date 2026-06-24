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

mapfile -t SITE_COMPOSE_FILES < <(find docker -maxdepth 2 -type f -path "docker/wp-site*/docker-compose.yml" | sort -Vr)

for compose_file in "${SITE_COMPOSE_FILES[@]}"; do
  site="$(basename "$(dirname "$compose_file")")"
  compose_cmd --project-name "$site" --env-file docker/.env -f "$compose_file" down
  echo "[ok] stopped ${site}"
done

compose_cmd --env-file docker/.env -f docker/redis/docker-compose.yml down
compose_cmd --env-file docker/.env -f docker/mariadb/docker-compose.yml down

echo "[ok] core services stopped"
