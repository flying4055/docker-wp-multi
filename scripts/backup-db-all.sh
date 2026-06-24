#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'EOF'
用法:
  ./scripts/backup-db-all.sh [--no-retention]

说明:
  - 自动发现 docker/.env 中所有站点，逐一备份数据库到 backups/ 目录
  - 同时备份 wp-content 目录（每个站点的上传文件/插件/主题）
  - 默认执行保留策略（7天内每日，30天内每周，180天内每月）
  - --no-retention 跳过自动清理

示例:
  ./scripts/backup-db-all.sh
  ./scripts/backup-db-all.sh --no-retention
EOF
}

# ── 参数解析 ──────────────────────────────────────────────

NO_RETENTION=false
if [[ "${1:-}" == "--no-retention" ]]; then
  NO_RETENTION=true
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ── 环境检查 ──────────────────────────────────────────────

if [[ ! -f docker/.env ]]; then
  echo "[error] 缺少 docker/.env，请先执行: cp docker/.env.example docker/.env"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx 'wp-mariadb'; then
  echo "[error] wp-mariadb 容器未运行，请先启动核心服务: ./scripts/up-core.sh"
  exit 1
fi

# ── 加载环境变量 ──────────────────────────────────────────

set -a
# shellcheck disable=SC1091
source docker/.env
set +a

# ── 发现所有站点 ──────────────────────────────────────────

SITE_NUMBERS=()
while IFS='=' read -r key _; do
  if [[ "$key" =~ ^MARIADB_SITE([0-9]+)_DB$ ]]; then
    SITE_NUMBERS+=("${BASH_REMATCH[1]}")
  fi
done < docker/.env

if [[ ${#SITE_NUMBERS[@]} -eq 0 ]]; then
  echo "[warn] docker/.env 中未发现任何站点 (MARIADB_SITE*_DB)"
  exit 0
fi

# 按数字排序
mapfile -t SITE_NUMBERS < <(printf '%s\n' "${SITE_NUMBERS[@]}" | sort -n)

echo "========================================="
echo "  批量备份开始 - $(date '+%Y-%m-%d %H:%M:%S')"
echo "  发现站点: ${SITE_NUMBERS[*]}"
echo "========================================="

# ── 逐个备份数据库 ────────────────────────────────────────

BACKUP_DIR="$PROJECT_ROOT/backups"
mkdir -p "$BACKUP_DIR"

DB_FAILED=()
DB_OK=()
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

for site_no in "${SITE_NUMBERS[@]}"; do
  echo ""
  echo "── 站点 ${site_no} ───────────────────────────────"

  DB_KEY="MARIADB_SITE${site_no}_DB"
  DB_NAME="${!DB_KEY:-}"

  if [[ -z "$DB_NAME" ]]; then
    echo "  [warn] 未找到 ${DB_KEY}，跳过"
    continue
  fi

  BACKUP_FILE="${BACKUP_DIR}/site${site_no}_db_${TIMESTAMP}.sql.gz"

  echo "  [info] 备份数据库: ${DB_NAME}"

  if docker exec -i wp-mariadb mariadb-dump \
    -uroot \
    -p"${MARIADB_ROOT_PASSWORD}" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --default-character-set=utf8mb4 \
    "${DB_NAME}" \
    | gzip > "${BACKUP_FILE}"; then

    if [[ -s "${BACKUP_FILE}" ]]; then
      echo "  [ok] DB 备份完成 ($(du -h "$BACKUP_FILE" | cut -f1))"
      DB_OK+=("$site_no")
    else
      echo "  [error] DB 备份文件为空"
      rm -f "$BACKUP_FILE"
      DB_FAILED+=("$site_no")
    fi
  else
    echo "  [error] DB 备份命令失败"
    rm -f "$BACKUP_FILE"
    DB_FAILED+=("$site_no")
  fi

  # ── 备份 wp-content（如果容器在运行） ──────────────────

  SITE_CONTAINER="wp-site${site_no}"
  if docker ps --format '{{.Names}}' | grep -qx "$SITE_CONTAINER"; then
    CONTENT_BACKUP="${BACKUP_DIR}/site${site_no}_wp-content_${TIMESTAMP}.tar.gz"
    echo "  [info] 备份 wp-content: ${SITE_CONTAINER}"

    if docker exec "$SITE_CONTAINER" tar -czf - -C /var/www/html wp-content 2>/dev/null > "${CONTENT_BACKUP}"; then
      if [[ -s "${CONTENT_BACKUP}" ]]; then
        echo "  [ok] wp-content 备份完成 ($(du -h "$CONTENT_BACKUP" | cut -f1))"
      else
        echo "  [warn] wp-content 备份为空，已删除"
        rm -f "$CONTENT_BACKUP"
      fi
    else
      echo "  [warn] wp-content 备份失败（容器可能无 tar 命令？）"
      rm -f "$CONTENT_BACKUP"
    fi
  else
    echo "  [warn] ${SITE_CONTAINER} 未运行，跳过 wp-content 备份"
  fi
done

# ── 保留策略（每个站点独立执行） ──────────────────────────

if [[ "$NO_RETENTION" == "false" ]]; then
  echo ""
  echo "── 执行保留策略 ─────────────────────────────────"

  NOW=$(date +%s)

  for site_no in "${SITE_NUMBERS[@]}"; do
    mapfile -t ALL_BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "site${site_no}_db_*.sql.gz" | sort -r)

    if [[ ${#ALL_BACKUPS[@]} -eq 0 ]]; then
      continue
    fi

    declare -A KEPT
    declare -A KEPT_WEEK
    declare -A KEPT_MONTH

    for f in "${ALL_BACKUPS[@]}"; do
      ts_str="${f##*site${site_no}_db_}"
      ts_str="${ts_str%%.sql.gz}"

      if [[ ! "$ts_str" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        KEPT["$f"]=1
        continue
      fi

      file_date="${ts_str%%_*}"
      file_time="${ts_str##*_}"
      file_epoch=$(date -d "${file_date:0:4}-${file_date:4:2}-${file_date:6:2} ${file_time:0:2}:${file_time:2:2}:${file_time:4:2}" +%s 2>/dev/null || echo 0)

      if [[ "$file_epoch" -eq 0 ]]; then
        KEPT["$f"]=1
        continue
      fi

      days_ago=$(( (NOW - file_epoch) / 86400 ))

      if [[ "$days_ago" -le 7 ]]; then
        KEPT["$f"]=1
      elif [[ "$days_ago" -le 30 ]]; then
        week_num="$(date -d "@${file_epoch}" +%U)"
        if [[ -z "${KEPT_WEEK["week_${week_num}"]:-}" ]]; then
          KEPT_WEEK["week_${week_num}"]=1
          KEPT["$f"]=1
        fi
      elif [[ "$days_ago" -le 180 ]]; then
        month_key="$(date -d "@${file_epoch}" +%Y%m)"
        if [[ -z "${KEPT_MONTH["$month_key"]:-}" ]]; then
          KEPT_MONTH["$month_key"]=1
          KEPT["$f"]=1
        fi
      fi
    done

    for f in "${ALL_BACKUPS[@]}"; do
      if [[ -z "${KEPT["$f"]:-}" ]]; then
        rm -f "$f"
        echo "  [del] $(basename "$f")"
      fi
    done

    # 同时清理过期的 wp-content 备份（规则同 DB）
    mapfile -t CONTENT_BACKUPS < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "site${site_no}_wp-content_*.tar.gz" | sort -r)
    declare -A CONTENT_KEPT
    declare -A CONTENT_WEEK
    declare -A CONTENT_MONTH

    for f in "${CONTENT_BACKUPS[@]}"; do
      ts_str="${f##*site${site_no}_wp-content_}"
      ts_str="${ts_str%%.tar.gz}"

      if [[ ! "$ts_str" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        CONTENT_KEPT["$f"]=1
        continue
      fi

      file_date="${ts_str%%_*}"
      file_time="${ts_str##*_}"
      file_epoch=$(date -d "${file_date:0:4}-${file_date:4:2}-${file_date:6:2} ${file_time:0:2}:${file_time:2:2}:${file_time:4:2}" +%s 2>/dev/null || echo 0)

      if [[ "$file_epoch" -eq 0 ]]; then
        CONTENT_KEPT["$f"]=1
        continue
      fi

      days_ago=$(( (NOW - file_epoch) / 86400 ))

      if [[ "$days_ago" -le 7 ]]; then
        CONTENT_KEPT["$f"]=1
      elif [[ "$days_ago" -le 30 ]]; then
        week_num="$(date -d "@${file_epoch}" +%U)"
        if [[ -z "${CONTENT_WEEK["week_${week_num}"]:-}" ]]; then
          CONTENT_WEEK["week_${week_num}"]=1
          CONTENT_KEPT["$f"]=1
        fi
      elif [[ "$days_ago" -le 180 ]]; then
        month_key="$(date -d "@${file_epoch}" +%Y%m)"
        if [[ -z "${CONTENT_MONTH["$month_key"]:-}" ]]; then
          CONTENT_MONTH["$month_key"]=1
          CONTENT_KEPT["$f"]=1
        fi
      fi
    done

    for f in "${CONTENT_BACKUPS[@]}"; do
      if [[ -z "${CONTENT_KEPT["$f"]:-}" ]]; then
        rm -f "$f"
        echo "  [del] $(basename "$f")"
      fi
    done
  done
fi

# ── 汇总报告 ──────────────────────────────────────────────

echo ""
echo "========================================="
echo "  批量备份完成 - $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo "  DB 成功: ${#DB_OK[@]} (站点: ${DB_OK[*]:-无})"
if [[ ${#DB_FAILED[@]} -gt 0 ]]; then
  echo "  DB 失败: ${#DB_FAILED[@]} (站点: ${DB_FAILED[*]})"
fi
echo "  备份目录: ${BACKUP_DIR}"
echo ""

# 列出本次产生的备份文件
echo "本次备份文件:"
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name "*_${TIMESTAMP}.sql.gz" -o -name "*_${TIMESTAMP}.tar.gz" \) -exec ls -lh {} \; 2>/dev/null || echo "  (无)"

if [[ ${#DB_FAILED[@]} -gt 0 ]]; then
  exit 1
fi
