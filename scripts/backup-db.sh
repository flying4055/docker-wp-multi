#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/lib/compose.sh"

usage() {
  cat <<'EOF'
用法:
  ./scripts/backup-db.sh <site_number> [--no-retention]

说明:
  - 备份指定站点的 MariaDB 数据库到 backups/ 目录
  - 默认自动清理过期备份（7天内保留每日，30天内保留每周，180天内保留每月）
  - --no-retention 跳过自动清理

示例:
  ./scripts/backup-db.sh 1
  ./scripts/backup-db.sh 3 --no-retention
EOF
}

# ── 参数解析 ──────────────────────────────────────────────

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

SITE_NO="$1"
NO_RETENTION=false
if [[ "${2:-}" == "--no-retention" ]]; then
  NO_RETENTION=true
fi

if ! [[ "$SITE_NO" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] site_number 必须是正整数，例如 1"
  exit 1
fi

# ── 环境检查 ──────────────────────────────────────────────

if [[ ! -f docker/.env ]]; then
  echo "[error] 缺少 docker/.env，请先执行: cp docker/.env.example docker/.env"
  exit 1
fi

init_compose_cmd

# 检查 mariadb 容器是否运行
if ! docker ps --format '{{.Names}}' | grep -qx 'wp-mariadb'; then
  echo "[error] wp-mariadb 容器未运行，请先启动核心服务: ./scripts/up-core.sh"
  exit 1
fi

# ── 加载环境变量 ──────────────────────────────────────────

set -a
# shellcheck disable=SC1091
source docker/.env
set +a

DB_KEY="MARIADB_SITE${SITE_NO}_DB"
DB_NAME="${!DB_KEY:-}"

if [[ -z "$DB_NAME" ]]; then
  echo "[error] docker/.env 中未定义 ${DB_KEY}，请确认站点 ${SITE_NO} 已创建"
  exit 1
fi

# ── 执行备份 ──────────────────────────────────────────────

BACKUP_DIR="$PROJECT_ROOT/backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/site${SITE_NO}_db_${TIMESTAMP}.sql.gz"

echo "[info] 开始备份: ${DB_NAME} → ${BACKUP_FILE}"

# 通过 docker exec 执行 mariadb-dump，直接压缩输出
docker exec -i wp-mariadb mariadb-dump \
  -uroot \
  -p"${MARIADB_ROOT_PASSWORD}" \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --default-character-set=utf8mb4 \
  "${DB_NAME}" \
  | gzip > "${BACKUP_FILE}"

if [[ ${PIPESTATUS[0]} -eq 0 && -s "${BACKUP_FILE}" ]]; then
  echo "[ok] 备份完成 ($(du -h "$BACKUP_FILE" | cut -f1))"
else
  echo "[error] 备份失败"
  rm -f "$BACKUP_FILE"
  exit 1
fi

# ── 备份保留策略 ──────────────────────────────────────────

if [[ "$NO_RETENTION" == "false" ]]; then
  echo "[info] 执行备份保留策略..."

  # 收集该站点所有备份文件（按时间倒序，最新的在前）
  mapfile -t ALL_BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "site${SITE_NO}_db_*.sql.gz" | sort -r)

  declare -A KEPT
  NOW=$(date +%s)

  for f in "${ALL_BACKUPS[@]}"; do
    # 从文件名提取时间戳: site1_db_20250624_120000.sql.gz
    local_ts="$f"
    ts_str="${local_ts##*site${SITE_NO}_db_}"
    ts_str="${ts_str%%.sql.gz}"

    if [[ ! "$ts_str" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
      # 无法解析时间戳，保留
      KEPT["$f"]=1
      continue
    fi

    file_date="${ts_str%%_*}"        # 20250624
    file_time="${ts_str##*_}"        # 120000
    file_epoch=$(date -d "${file_date:0:4}-${file_date:4:2}-${file_date:6:2} ${file_time:0:2}:${file_time:2:2}:${file_time:4:2}" +%s 2>/dev/null || echo 0)

    if [[ "$file_epoch" -eq 0 ]]; then
      KEPT["$f"]=1
      continue
    fi

    days_ago=$(( (NOW - file_epoch) / 86400 ))

    if [[ "$days_ago" -le 7 ]]; then
      # 7天内：全部保留
      KEPT["$f"]=1
    elif [[ "$days_ago" -le 30 ]]; then
      # 8-30天：每周保留一份（周日 = week 53）
      week_num="$(date -d "@${file_epoch}" +%U)"
      week_key="week_${week_num}"
      if [[ -z "${KEPT_WEEK["$week_key"]:-}" ]]; then
        KEPT_WEEK["$week_key"]=1
        KEPT["$f"]=1
      fi
    elif [[ "$days_ago" -le 180 ]]; then
      # 31-180天：每月保留一份
      month_key="$(date -d "@${file_epoch}" +%Y%m)"
      if [[ -z "${KEPT_MONTH["$month_key"]:-}" ]]; then
        KEPT_MONTH["$month_key"]=1
        KEPT["$f"]=1
      fi
    fi
    # 超过180天的不保留
  done

  # 删除未标记保留的备份
  DELETED=0
  for f in "${ALL_BACKUPS[@]}"; do
    if [[ -z "${KEPT["$f"]:-}" ]]; then
      rm -f "$f"
      echo "  [del] $(basename "$f")"
      ((DELETED++)) || true
    fi
  done

  if [[ "$DELETED" -eq 0 ]]; then
    echo "  [info] 无需清理"
  else
    echo "  [ok] 已清理 ${DELETED} 份过期备份"
  fi
fi

echo "[done]"
