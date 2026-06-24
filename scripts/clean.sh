#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/lib/compose.sh"

usage() {
  cat <<'EOF'
用法:
  ./scripts/clean.sh [--reset-env]

说明:
  - 停止并删除本项目所有容器
  - 删除 MariaDB/Redis 数据卷（清空数据库与缓存数据）
  - 删除项目 Docker 网络（若未被占用）
  - 可选恢复 docker/.env 为 docker/.env.example

示例:
  ./scripts/clean.sh
  ./scripts/clean.sh --reset-env
EOF
}

RESET_ENV="false"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--reset-env" ]]; then
  RESET_ENV="true"
fi

ENV_FILE="docker/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f docker/.env.example ]]; then
    ENV_FILE="docker/.env.example"
    echo "[warn] docker/.env 不存在，改用 docker/.env.example 执行清理"
  else
    echo "[error] 缺少 docker/.env 和 docker/.env.example"
    exit 1
  fi
fi

init_compose_cmd

mapfile -t SITE_COMPOSE_FILES < <(find docker -maxdepth 2 -type f -path "docker/wp-site*/docker-compose.yml" | sort -Vr)
CORE_COMPOSE_FILES=(
  docker/redis/docker-compose.yml
  docker/mariadb/docker-compose.yml
)

for compose_file in "${SITE_COMPOSE_FILES[@]}" "${CORE_COMPOSE_FILES[@]}"; do
  [[ -f "$compose_file" ]] || continue
  project="$(basename "$(dirname "$compose_file")")"
  compose_cmd --project-name "$project" --env-file "$ENV_FILE" -f "$compose_file" down -v --remove-orphans || true
  echo "[ok] cleaned ${project}"
done

NETWORK_NAME="$(grep -E '^WORDPRESS_NETWORK=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
if [[ -n "$NETWORK_NAME" ]]; then
  docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
fi

if [[ "$RESET_ENV" == "true" ]]; then
  if [[ -f docker/.env.example ]]; then
    cp docker/.env.example docker/.env
    echo "[ok] docker/.env 已重置为 docker/.env.example"
  else
    echo "[warn] 未找到 docker/.env.example，跳过 .env 重置"
  fi
fi

echo "[done] 环境已清理，可重新执行 ./scripts/up-all.sh"
