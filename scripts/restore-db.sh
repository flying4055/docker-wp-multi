#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'EOF'
用法:
  ./scripts/restore-db.sh <site_number>                 从最新备份恢复
  ./scripts/restore-db.sh <site_number> <backup_file>   从指定备份文件恢复
  ./scripts/restore-db.sh --list                        列出所有备份文件

选项:
  -f, --force     跳过确认提示，直接执行恢复
  --dry-run       仅显示将要执行的操作，不实际恢复

示例:
  ./scripts/restore-db.sh 1                              # 恢复站点1（使用最新备份，需确认）
  ./scripts/restore-db.sh 1 -f                           # 强制恢复，跳过确认
  ./scripts/restore-db.sh 1 backups/site1_db_20250624_120000.sql.gz  # 恢复指定文件
  ./scripts/restore-db.sh --list                         # 列出所有备份
  ./scripts/restore-db.sh --list site1                   # 列出站点1的所有备份
EOF
}

# ── list 模式 ─────────────────────────────────────────────

if [[ "${1:-}" == "--list" ]]; then
  BACKUP_DIR="$PROJECT_ROOT/backups"
  FILTER="${2:-}"

  echo "备份文件列表:"
  echo ""

  if [[ -n "$FILTER" ]]; then
    echo "  [数据库备份]"
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "${FILTER}_db_*.sql.gz" | sort -r | while read -r f; do
      printf "    %s  (%s)\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done
    echo ""
    echo "  [wp-content 备份]"
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "${FILTER}_wp-content_*.tar.gz" | sort -r | while read -r f; do
      printf "    %s  (%s)\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done
  else
    echo "  [数据库备份]"
    find "$BACKUP_DIR" -maxdepth 1 -type f -name '*_db_*.sql.gz' | sort -r | while read -r f; do
      printf "    %s  (%s)\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done
    echo ""
    echo "  [wp-content 备份]"
    find "$BACKUP_DIR" -maxdepth 1 -type f -name '*_wp-content_*.tar.gz' | sort -r | while read -r f; do
      printf "    %s  (%s)\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
    done
  fi
  exit 0
fi

# ── 参数解析 ──────────────────────────────────────────────

FORCE=false
DRY_RUN=false
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
BACKUP_FILE="${args[1]:-}"  # 可选

if ! [[ "$SITE_NO" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] site_number 必须是正整数，例如 1"
  exit 1
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

DB_KEY="MARIADB_SITE${SITE_NO}_DB"
DB_NAME="${!DB_KEY:-}"

if [[ -z "$DB_NAME" ]]; then
  echo "[error] docker/.env 中未定义 ${DB_KEY}，请确认站点 ${SITE_NO} 已创建"
  exit 1
fi

# ── 确定备份文件 ──────────────────────────────────────────

BACKUP_DIR="$PROJECT_ROOT/backups"

if [[ -z "$BACKUP_FILE" ]]; then
  # 自动选择最新备份
  BACKUP_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "site${SITE_NO}_db_*.sql.gz" | sort -r | head -1)"

  if [[ -z "$BACKUP_FILE" ]]; then
    echo "[error] 未找到站点 ${SITE_NO} 的数据库备份文件"
    echo "        可用备份列表:"
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "site${SITE_NO}_db_*.sql.gz" | sort -r | while read -r f; do
      echo "          $(basename "$f")"
    done
    echo "        或手动指定: ./scripts/restore-db.sh ${SITE_NO} <backup_file>"
    exit 1
  fi

  echo "[info] 自动选择最新备份: $(basename "$BACKUP_FILE")"
else
  # 用户指定了备份文件
  if [[ ! -f "$BACKUP_FILE" ]]; then
    # 尝试在 backups/ 目录下查找
    if [[ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
      BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
    else
      echo "[error] 备份文件不存在: ${BACKUP_FILE}"
      exit 1
    fi
  fi

  # 验证文件名匹配站点号
  fname="$(basename "$BACKUP_FILE")"
  if [[ ! "$fname" =~ ^site${SITE_NO}_db_.*\.sql\.gz$ ]]; then
    echo "[warn] 备份文件名与站点号不匹配: ${fname}"
    echo "       期望前缀: site${SITE_NO}_db_"
    if [[ "$FORCE" != "true" ]]; then
      read -rp "       确认继续恢复? [y/N] " confirm
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "[info] 已取消"
        exit 0
      fi
    fi
  fi
fi

# ── 显示恢复信息 ──────────────────────────────────────────

echo ""
echo "========================================="
echo "  数据库恢复"
echo "========================================="
echo "  站点编号:   ${SITE_NO}"
echo "  数据库名:   ${DB_NAME}"
echo "  备份文件:   $(basename "$BACKUP_FILE")"
echo "  文件大小:   $(du -h "$BACKUP_FILE" | cut -f1)"
echo "  备份时间:   $(date -r "$BACKUP_FILE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '未知')"
echo "========================================="

# ── 检查目标数据库当前状态 ────────────────────────────────

TABLE_COUNT=$(docker exec wp-mariadb mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -sN -e \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}';" 2>/dev/null || echo "0")

if [[ "$TABLE_COUNT" =~ ^[0-9]+$ ]] && [[ "$TABLE_COUNT" -gt 0 ]]; then
  echo ""
  echo "  ⚠ 警告: 数据库 ${DB_NAME} 当前包含 ${TABLE_COUNT} 张表！"
  echo "  恢复操作将覆盖所有现有数据。"
fi

# ── 确认 ──────────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "  [dry-run] 将执行以下操作:"
  echo "    1. DROP + CREATE 数据库 ${DB_NAME}"
  echo "    2. gunzip < $(basename "$BACKUP_FILE") | mariadb"
  echo "  [dry-run] 未做任何实际修改"
  exit 0
fi

if [[ "$FORCE" != "true" ]]; then
  echo ""
  read -rp "  确认恢复数据库 ${DB_NAME}? 输入 YES 继续: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "[info] 已取消"
    exit 0
  fi
fi

# ── 执行恢复 ──────────────────────────────────────────────

echo ""
echo "[info] 开始恢复 ${DB_NAME}..."

# 先删除并重建数据库（清空所有现有数据）
docker exec -i wp-mariadb mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
SQL

echo "[info] 导入备份数据..."

# 解压并导入
if gunzip -c "$BACKUP_FILE" | docker exec -i wp-mariadb mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" "${DB_NAME}"; then
  echo "[ok] 数据库恢复完成: ${DB_NAME}"

  # 验证恢复结果
  VERIFY_COUNT=$(docker exec wp-mariadb mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" -sN -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}';" 2>/dev/null || echo "0")
  echo "[info] 恢复后表数量: ${VERIFY_COUNT}"

  # 确保用户权限正确
  USER_KEY="MARIADB_SITE${SITE_NO}_USER"
  DB_USER="${!USER_KEY:-wp_site${SITE_NO}_user}"

  docker exec -i wp-mariadb mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
  echo "[info] 已刷新用户权限 (${DB_USER})"
else
  echo "[error] 数据库恢复失败！"
  echo "        请检查备份文件是否完整: $(basename "$BACKUP_FILE")"
  echo "        可尝试手动: gunzip -c $BACKUP_FILE | docker exec -i wp-mariadb mariadb -uroot -p \"${DB_NAME}\""
  exit 1
fi

echo ""
echo "[done] 站点 ${SITE_NO} 数据库已恢复"
echo "       如需同时恢复 wp-content，请手动解压对应 .tar.gz 到容器"
