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

CORE_COMPOSE_FILES=(
  docker/mariadb/docker-compose.yml
  docker/redis/docker-compose.yml
)

mapfile -t SITE_COMPOSE_FILES < <(find docker -maxdepth 2 -type f -path "docker/wp-site*/docker-compose.yml" | sort -V)

for compose_file in "${CORE_COMPOSE_FILES[@]}" "${SITE_COMPOSE_FILES[@]}"; do
  [[ -f "$compose_file" ]] || continue
  printf '\n=== %s ===\n' "${compose_file}"
  compose_cmd --env-file docker/.env -f "${compose_file}" ps || true
done
