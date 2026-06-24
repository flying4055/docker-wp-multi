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

mapfile -t SITE_COMPOSE_FILES < <(find docker -maxdepth 2 -type f -path "docker/wp-site*/docker-compose.yml" | sort -V)

if [[ ${#SITE_COMPOSE_FILES[@]} -eq 0 ]]; then
  echo "[warn] no site compose files found under docker/wp-site*/docker-compose.yml"
  exit 0
fi

for compose_file in "${SITE_COMPOSE_FILES[@]}"; do
  site="$(basename "$(dirname "$compose_file")")"
  compose_cmd --project-name "$site" --env-file docker/.env -f "$compose_file" up -d
  echo "[ok] started ${site}"
done
