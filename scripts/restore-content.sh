#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

usage() {
  cat <<'EOF'
用法:
  ./scripts/restore-content.sh <site_number>                 从最新备份恢复
  ./scripts/restore-content.sh <site_number> <backup_file>   从指定备份文件恢复

选项:
  -f, --force     跳过确认提示，直接执行恢复
  --dry-run       仅显示将要执行的操作，不实际恢复

说明:
  - 恢复 wp-content 目录（上传文件、插件、主题）到指定站点容器
  - 恢复前会先备份容器内当前 wp-content 到 backups/（带 .pre-restore 后缀）

示例:
  ./scripts/restore-content.sh 1                              # 恢复站点1（使用最新备份）
  ./scripts/restore-content.sh 1 -f                           # 强制恢复
  ./scripts/restore-content.sh 1 backups/site1_wp-content_20250624_120000.tar.gz
EOF
}

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
BACKUP_FILE="${args[1]:-}"

if ! [[ "$SITE_NO" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] site_number 必须是正整数，例如 1"
  exit 1
fi

# ── 环境检查 ──────────────────────────────────────────────

SITE_CONTAINER="wp-site${SITE_NO}"

if ! docker ps --format '{{.Names}}' | grep -qx "$SITE_CONTAINER"; then
  echo "[error] ${SITE_CONTAINER} 容器未运行，请先启动: ./scripts/site.sh ${SITE_NO} up"
  exit 1
fi

# ── 确定备份文件 ──────────────────────────────────────────

BACKUP_DIR="$PROJECT_ROOT/backups"

if [[ -z "$BACKUP_FILE" ]]; then
  BACKUP_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "site${SITE_NO}_wp-content_*.tar.gz" | sort -r | head -1)"

  if [[ -z "$BACKUP_FILE" ]]; then
    echo "[error] 未找到站点 ${SITE_NO} 的 wp-content 备份文件"
    echo "        可用备份列表:"
    find "$BACKUP_DIR" -maxdepth 1 -type f -name "site${SITE_NO}_wp-content_*.tar.gz" | sort -r | while read -r f; do
      echo "          $(basename "$f")"
    done
    exit 1
  fi

  echo "[info] 自动选择最新备份: $(basename "$BACKUP_FILE")"
else
  if [[ ! -f "$BACKUP_FILE" ]]; then
    if [[ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]]; then
      BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
    else
      echo "[error] 备份文件不存在: ${BACKUP_FILE}"
      exit 1
    fi
  fi
fi

# ── 显示恢复信息 ──────────────────────────────────────────

echo ""
echo "========================================="
echo "  wp-content 恢复"
echo "========================================="
echo "  站点容器:   ${SITE_CONTAINER}"
echo "  备份文件:   $(basename "$BACKUP_FILE")"
echo "  文件大小:   $(du -h "$BACKUP_FILE" | cut -f1)"
echo "  备份时间:   $(date -r "$BACKUP_FILE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '未知')"
echo "========================================="

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "  [dry-run] 将执行以下操作:"
  echo "    1. 备份当前 wp-content 到 backups/ (安全措施)"
  echo "    2. tar -xzf $(basename "$BACKUP_FILE") 到容器 /var/www/html/"
  echo "  [dry-run] 未做任何实际修改"
  exit 0
fi

if [[ "$FORCE" != "true" ]]; then
  echo ""
  read -rp "  确认恢复 wp-content (将覆盖当前文件)? 输入 YES 继续: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "[info] 已取消"
    exit 0
  fi
fi

# ── 安全措施：先备份当前 wp-content ───────────────────────

PRE_RESTORE_BACKUP="${BACKUP_DIR}/site${SITE_NO}_wp-content_pre-restore_$(date +%Y%m%d_%H%M%S).tar.gz"

echo ""
echo "[info] 安全措施: 先备份当前 wp-content..."
echo "        → $(basename "$PRE_RESTORE_BACKUP")"

if docker exec "$SITE_CONTAINER" tar -czf - -C /var/www/html wp-content 2>/dev/null > "$PRE_RESTORE_BACKUP"; then
  if [[ -s "$PRE_RESTORE_BACKUP" ]]; then
    echo "  [ok] 当前 wp-content 已备份 ($(du -h "$PRE_RESTORE_BACKUP" | cut -f1))"
  else
    echo "  [warn] 当前 wp-content 备份为空"
    rm -f "$PRE_RESTORE_BACKUP"
  fi
else
  echo "  [warn] 当前 wp-content 备份失败，继续恢复..."
  rm -f "$PRE_RESTORE_BACKUP"
fi

# ── 执行恢复 ──────────────────────────────────────────────

echo "[info] 恢复 wp-content 到 ${SITE_CONTAINER}..."

if gunzip -c "$BACKUP_FILE" | docker exec -i "$SITE_CONTAINER" tar -xf - -C /var/www/html/; then
  echo "[ok] wp-content 恢复完成"
else
  echo "[error] wp-content 恢复失败！"
  echo "        可尝试手动: gunzip -c $BACKUP_FILE | docker exec -i ${SITE_CONTAINER} tar -xf - -C /var/www/html/"
  exit 1
fi

echo ""
echo "[done] 站点 ${SITE_NO} wp-content 已恢复"
