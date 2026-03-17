#!/usr/bin/env bash
# shellcheck shell=bash

# 统一封装 Compose 命令：
# - 优先使用 `docker compose`（Docker Compose V2 插件）
# - 回退到 `docker-compose`（仅支持 V2）

if [[ -n "${_WP_COMPOSE_LIB_LOADED:-}" ]]; then
  return 0
fi
_WP_COMPOSE_LIB_LOADED=1

declare -ag COMPOSE_CMD=()

init_compose_cmd() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[error] 未找到 docker 命令，请先安装 Docker 26+"
    return 1
  fi

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=("docker" "compose")
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    local compose_version
    compose_version="$(docker-compose version --short 2>/dev/null || true)"
    if [[ "$compose_version" =~ ^v?2(\.|$) ]]; then
      COMPOSE_CMD=("docker-compose")
      return 0
    fi
    echo "[error] 检测到 docker-compose v1（${compose_version:-unknown}），仅支持 docker-compose v2"
    return 1
  fi

  echo "[error] 未检测到 Compose V2。请安装 Docker Compose V2（`docker compose` 或 `docker-compose v2`）"
  return 1
}

compose_cmd() {
  if [[ ${#COMPOSE_CMD[@]} -eq 0 ]]; then
    echo "[error] Compose 未初始化，请先调用 init_compose_cmd"
    return 1
  fi
  "${COMPOSE_CMD[@]}" "$@"
}

