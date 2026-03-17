#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/lib/compose.sh"

usage() {
  cat <<'EOF'
用法:
  ./scripts/add-site.sh <site_number> [domain] [port]

示例:
  ./scripts/add-site.sh 4
  ./scripts/add-site.sh 5 site5.yourdomain.com 8085
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

SITE_NO="$1"
DOMAIN="${2:-}"
PORT="${3:-}"

if ! [[ "$SITE_NO" =~ ^[1-9][0-9]*$ ]]; then
  echo "[error] site_number 必须是正整数，例如 4"
  exit 1
fi

if [[ -z "$PORT" ]]; then
  PORT=$((8080 + SITE_NO))
fi

if [[ -z "$DOMAIN" ]]; then
  DOMAIN="site${SITE_NO}.example.com"
fi

if [[ ! -f docker/.env ]]; then
  echo "[error] 缺少 docker/.env，请先执行: cp docker/.env.example docker/.env"
  exit 1
fi

init_compose_cmd

SITE_NAME="wp-site${SITE_NO}"
SITE_DIR="docker/${SITE_NAME}"
COMPOSE_FILE="${SITE_DIR}/docker-compose.yml"
NGINX_FILE="nginx/site${SITE_NO}.conf"

DB_KEY="MARIADB_SITE${SITE_NO}_DB"
USER_KEY="MARIADB_SITE${SITE_NO}_USER"
PASS_KEY="MARIADB_SITE${SITE_NO}_PASSWORD"
PORT_KEY="WP_SITE${SITE_NO}_PORT"

DB_NAME="wp_site${SITE_NO}"
DB_USER="wp_site${SITE_NO}_user"
DB_PASS="TODO_CHANGE_ME_SITE${SITE_NO}_DB_PASSWORD"

append_kv_if_missing() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -Eq "^${key}=" "$file"; then
    echo "[skip] ${file} 已存在 ${key}"
  else
    echo "${key}=${value}" >> "$file"
    echo "[ok] 写入 ${file}: ${key}"
  fi
}

if [[ -e "$SITE_DIR" ]]; then
  echo "[error] ${SITE_DIR} 已存在"
  exit 1
fi

mkdir -p "${SITE_DIR}/wp-content"

cat > "$COMPOSE_FILE" <<EOF
services:
  wordpress:
    image: \${WORDPRESS_IMAGE}
    container_name: ${SITE_NAME}
    restart: unless-stopped
    env_file:
      - ../.env
    ports:
      - "\${${PORT_KEY}}:80"
    environment:
      TZ: \${TZ}
      WORDPRESS_DB_HOST: wp-mariadb:3306
      WORDPRESS_DB_NAME: \${${DB_KEY}}
      WORDPRESS_DB_USER: \${${USER_KEY}}
      WORDPRESS_DB_PASSWORD: \${${PASS_KEY}}
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_REDIS_HOST', 'wp-redis');
        define('WP_REDIS_PORT', 6379);
        define('WP_REDIS_PASSWORD', '\${REDIS_PASSWORD}');
        define('WP_CACHE', true);
        define('FORCE_SSL_ADMIN', true);
        if (isset(\$$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
          \$$_SERVER['HTTPS'] = 'on';
        }
    volumes:
      - ./wp-content:/var/www/html/wp-content
    healthcheck:
      test: ["CMD", "php", "-v"]
      interval: 30s
      timeout: 10s
      retries: 5
    networks:
      - wordpress-network

networks:
  wordpress-network:
    external: true
    name: \${WORDPRESS_NETWORK}
EOF

cat > "$NGINX_FILE" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size 64m;

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }
}
EOF

append_kv_if_missing docker/.env "$DB_KEY" "$DB_NAME"
append_kv_if_missing docker/.env "$USER_KEY" "$DB_USER"
append_kv_if_missing docker/.env "$PASS_KEY" "$DB_PASS"
append_kv_if_missing docker/.env "$PORT_KEY" "$PORT"

if [[ -f docker/.env.example ]]; then
  append_kv_if_missing docker/.env.example "$DB_KEY" "$DB_NAME"
  append_kv_if_missing docker/.env.example "$USER_KEY" "$DB_USER"
  append_kv_if_missing docker/.env.example "$PASS_KEY" "$DB_PASS"
  append_kv_if_missing docker/.env.example "$PORT_KEY" "$PORT"
fi

set -a
# shellcheck disable=SC1091
source docker/.env
set +a

DB_NAME_VALUE="${!DB_KEY}"
DB_USER_VALUE="${!USER_KEY}"
DB_PASS_VALUE="${!PASS_KEY}"

if docker ps --format '{{.Names}}' | grep -qx 'wp-mariadb'; then
  docker exec -i wp-mariadb mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME_VALUE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER_VALUE}'@'%' IDENTIFIED BY '${DB_PASS_VALUE}';
GRANT ALL PRIVILEGES ON \`${DB_NAME_VALUE}\`.* TO '${DB_USER_VALUE}'@'%';
FLUSH PRIVILEGES;
SQL
  echo "[ok] 已在 MariaDB 中创建数据库和用户 (${DB_NAME_VALUE})"
else
  echo "[warn] wp-mariadb 未运行，已跳过数据库创建。"
  echo "       启动核心服务后可手动执行 ./scripts/add-site.sh ${SITE_NO} ${DOMAIN} ${PORT} 重试 DB 创建。"
fi

if docker ps --format '{{.Names}}' | grep -qx 'wp-redis' && docker ps --format '{{.Names}}' | grep -qx 'wp-mariadb'; then
  compose_cmd --env-file docker/.env -f "$COMPOSE_FILE" up -d
  echo "[ok] ${SITE_NAME} 已启动"
else
  echo "[warn] 核心服务未完全运行，暂未启动 ${SITE_NAME}。"
  echo "       请先执行 ./scripts/up-core.sh，然后 ./scripts/up-sites.sh"
fi

echo "[done] 新站点已创建:"
echo "       - Compose: ${COMPOSE_FILE}"
echo "       - Nginx:   ${NGINX_FILE}"
echo "       - Domain:  ${DOMAIN}"
echo "       - Port:    ${PORT}"
