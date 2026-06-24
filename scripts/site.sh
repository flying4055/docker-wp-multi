#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/lib/compose.sh"

usage() {
  cat <<'EOF'
用法:
  ./scripts/site.sh <site_number> <action> [args]

action:
  up            启动/拉起单站点
  restart       仅重启单站点容器进程
  recreate      强制重建并启动（用于加载新的 .env）
  stop          停止单站点
  down          停止并删除单站点容器
  ps            查看单站点状态
  logs [tail]   查看单站点日志（默认 tail=100）

示例:
  ./scripts/site.sh 3 up
  ./scripts/site.sh 3 restart
  ./scripts/site.sh 3 recreate
  ./scripts/site.sh 3 logs 200
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
  usage
  exit 0
fi

SITE_NO="$1"
ACTION="$2"
shift 2

if ! [[ "$SITE_NO" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] site_number 必须是正整数，例如 3"
  exit 1
fi

if [[ ! -f docker/.env ]]; then
  echo "[error] 缺少 docker/.env，请先执行: cp docker/.env.example docker/.env"
  exit 1
fi

init_compose_cmd

COMPOSE_FILE="docker/wp-site${SITE_NO}/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[error] 未找到站点配置: ${COMPOSE_FILE}"
  exit 1
fi

PROJECT_NAME="wp-site${SITE_NO}"

dc() {
  compose_cmd --project-name "$PROJECT_NAME" --env-file docker/.env -f "$COMPOSE_FILE" "$@"
}

case "$ACTION" in
  up)
    dc up -d
    ;;
  restart)
    dc restart
    ;;
  recreate)
    dc up -d --force-recreate
    ;;
  stop)
    dc stop
    ;;
  down)
    dc down
    ;;
  ps|status)
    dc ps
    ;;
  logs)
    tail_lines="${1:-100}"
    dc logs --tail "$tail_lines" -f
    ;;
  *)
    echo "[error] 不支持的 action: $ACTION"
    usage
    exit 1
    ;;
esac
