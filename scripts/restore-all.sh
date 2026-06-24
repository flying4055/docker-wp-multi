#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'EOF'
用法:
  ./scripts/restore-all.sh <site_number>                 从最新备份恢复（DB + wp-content）
  ./scripts/restore-all.sh <site_number> <timestamp>     从指定时间戳恢复

选项:
  -f, --force        跳过确认提示，直接执行恢复
  --db-only          仅恢复数据库
  --content-only     仅恢复 wp-content
  --dry-run          仅显示将要执行的操作

说明:
  - 同时恢复数据库和 wp-content（完整站点恢复）
  - <timestamp> 格式: 20250624_120000（备份文件名中的时间戳部分）
  - 恢复前会自动备份当前 wp-content 到 backups/

示例:
  ./scripts/restore-all.sh 1                              # 恢复站点1全部（最新备份）
  ./scripts/restore-all.sh 1 20250624_120000              # 恢复到指定时间点
  ./scripts/restore-all.sh 1 --db-only                    # 仅恢复数据库
  ./scripts/restore-all.sh 1 --content-only -f            # 强制仅恢复文件
EOF
}

# ── 参数解析 ──────────────────────────────────────────────

FORCE=false
DRY_RUN=false
DB_ONLY=false
CONTENT_ONLY=false
args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage; exit 0
      ;;
    -f|--force)
      FORCE=true; shift
      ;;
    --dry-run)
      DRY_RUN=true; shift
      ;;
    --db-only)
      DB_ONLY=true; shift
      ;;
    --content-only)
      CONTENT_ONLY=true; shift
      ;;
    -*)
      echo "[error] 未知选项: $1"
      usage; exit 1
      ;;
    *)
      args+=("$1"); shift
      ;;
  esac
done

if [[ ${#args[@]} -lt 1 ]]; then
  usage
  exit 1
fi

SITE_NO="${args[0]}"
TIMESTAMP="${args[1]:-}"

if ! [[ "$SITE_NO" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] site_number 必须是正整数，例如 1"
  exit 1
fi

# ── 环境检查 ──────────────────────────────────────────────

if [[ ! -f docker/.env ]]; then
  echo "[error] 缺少 docker/.env，请先执行: cp docker/.env.example docker/.env"
  exit 1
fi

# ── 确定备份文件 ──────────────────────────────────────────

BACKUP_DIR="$PROJECT_ROOT/backups"

find_backup() {
  local pattern="$1"
  if [[ -n "$TIMESTAMP" ]]; then
    # 精确匹配时间戳
    local f="${BACKUP_DIR}/${pattern}_${TIMESTAMP}.sql.gz"
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
    f="${BACKUP_DIR}/${pattern}_${TIMESTAMP}.tar.gz"
    if [[ -f "$f" ]]; then
      echo "$f"
      return 0
    fi
    echo ""
    return 1
  else
    # 最新
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "${pattern}_*.sql.gz" -o -name "${pattern}_*.tar.gz" 2>/dev/null \
      | sort -r | head -1
  fi
}

SITE_PREFIX="site${SITE_NO}"

if [[ "$DB_ONLY" == "true" ]]; then
  # 仅 DB
  if [[ -n "$TIMESTAMP" ]]; then
    DB_FILE="${BACKUP_DIR}/${SITE_PREFIX}_db_${TIMESTAMP}.sql.gz"
  else
    DB_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${SITE_PREFIX}_db_*.sql.gz" | sort -r | head -1)"
  fi
  if [[ ! -f "$DB_FILE" ]]; then
    echo "[error] 未找到数据库备份"
    exit 1
  fi
  CONTENT_FILE=""
elif [[ "$CONTENT_ONLY" == "true" ]]; then
  # 仅 content
  DB_FILE=""
  if [[ -n "$TIMESTAMP" ]]; then
    CONTENT_FILE="${BACKUP_DIR}/${SITE_PREFIX}_wp-content_${TIMESTAMP}.tar.gz"
  else
    CONTENT_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${SITE_PREFIX}_wp-content_*.tar.gz" | sort -r | head -1)"
  fi
  if [[ ! -f "$CONTENT_FILE" ]]; then
    echo "[error] 未找到 wp-content 备份"
    exit 1
  fi
else
  # 全量
  if [[ -n "$TIMESTAMP" ]]; then
    DB_FILE="${BACKUP_DIR}/${SITE_PREFIX}_db_${TIMESTAMP}.sql.gz"
    CONTENT_FILE="${BACKUP_DIR}/${SITE_PREFIX}_wp-content_${TIMESTAMP}.tar.gz"
  else
    DB_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${SITE_PREFIX}_db_*.sql.gz" | sort -r | head -1)"
    CONTENT_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${SITE_PREFIX}_wp-content_*.tar.gz" | sort -r | head -1)"
  fi
fi

# ── 显示恢复计划 ──────────────────────────────────────────

echo ""
echo "========================================="
echo "  完整站点恢复 - 站点 ${SITE_NO}"
echo "========================================="

if [[ -n "$DB_FILE" ]] && [[ -f "$DB_FILE" ]]; then
  echo "  [DB]  $(basename "$DB_FILE")  ($(du -h "$DB_FILE" | cut -f1))"
elif [[ "$CONTENT_ONLY" != "true" ]]; then
  echo "  [DB]  ⚠ 未找到备份文件"
fi

if [[ -n "$CONTENT_FILE" ]] && [[ -f "$CONTENT_FILE" ]]; then
  echo "  [文件] $(basename "$CONTENT_FILE")  ($(du -h "$CONTENT_FILE" | cut -f1))"
elif [[ "$DB_ONLY" != "true" ]]; then
  echo "  [文件] ⚠ 未找到备份文件"
fi

echo "========================================="

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "  [dry-run] 以上是将要恢复的备份文件"
  exit 0
fi

# ── 确认 ──────────────────────────────────────────────────

if [[ "$FORCE" != "true" ]]; then
  echo ""
  read -rp "  确认执行恢复? 输入 YES 继续: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "[info] 已取消"
    exit 0
  fi
fi

# ── 执行恢复 ──────────────────────────────────────────────

FAILED=()

# 恢复数据库
if [[ -n "$DB_FILE" ]] && [[ -f "$DB_FILE" ]]; then
  echo ""
  echo "── 第1步: 恢复数据库 ──────────────────────────"

  if docker ps --format '{{.Names}}' | grep -qx 'wp-mariadb'; then
    set -a
    # shellcheck disable=SC1091
    source docker/.env
    set +a

    DB_KEY="MARIADB_SITE${SITE_NO}_DB"
    DB_NAME="${!DB_KEY:-wp_site${SITE_NO}}"

    RESTORE_CMD=()

    if [[ "$FORCE" == "true" ]]; then
      RESTORE_CMD+=(-f)
    fi

    "$PROJECT_ROOT/scripts/restore-db.sh" "$SITE_NO" "$DB_FILE" "${RESTORE_CMD[@]}" || {
      echo "[error] 数据库恢复失败"
      FAILED+=("DB")
    }
  else
    echo "[error] wp-mariadb 未运行，跳过数据库恢复"
    FAILED+=("DB")
  fi
else
  echo "[warn] 跳过数据库恢复（未找到备份文件）"
fi

# 恢复 wp-content
if [[ -n "$CONTENT_FILE" ]] && [[ -f "$CONTENT_FILE" ]]; then
  echo ""
  echo "── 第2步: 恢复 wp-content ──────────────────────"

  if docker ps --format '{{.Names}}' | grep -qx "wp-site${SITE_NO}"; then
    RESTORE_CMD=()
    if [[ "$FORCE" == "true" ]]; then
      RESTORE_CMD+=(-f)
    fi

    "$PROJECT_ROOT/scripts/restore-content.sh" "$SITE_NO" "$CONTENT_FILE" "${RESTORE_CMD[@]}" || {
      echo "[error] wp-content 恢复失败"
      FAILED+=("wp-content")
    }
  else
    echo "[warn] wp-site${SITE_NO} 未运行，跳过 wp-content 恢复"
    echo "       请先启动: ./scripts/site.sh ${SITE_NO} up"
    FAILED+=("wp-content")
  fi
else
  echo "[warn] 跳过 wp-content 恢复（未找到备份文件）"
fi

# ── 汇总 ──────────────────────────────────────────────────

echo ""
echo "========================================="
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "  ✅ 站点 ${SITE_NO} 恢复完成"
else
  echo "  ⚠ 部分恢复失败: ${FAILED[*]}"
fi
echo "========================================="
echo ""

if [[ ${#FAILED[@]} -gt 0 ]]; then
  exit 1
fi
