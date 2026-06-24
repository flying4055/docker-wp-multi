# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project summary

Docker-based WordPress multi-site deployment with isolated containers per site, shared MariaDB + Redis, and Nginx reverse proxy. All services run on a single explicit `wordpress-network` (external Docker network).

## Key commands

```bash
# First-time setup
cp docker/.env.example docker/.env   # then edit all TODO_ passwords
./scripts/up-all.sh                  # start everything (network → core → sites)

# Day-to-day operations
./scripts/status.sh                  # show all container states
./scripts/site.sh 3 up               # start a single site
./scripts/site.sh 3 restart          # restart container process (no env reload)
./scripts/site.sh 3 recreate         # force-recreate to pick up .env changes
./scripts/site.sh 3 logs 200         # tail logs for a single site
./scripts/down-all.sh                # stop everything

# Adding a site
./scripts/add-site.sh 4                              # auto-generate compose + nginx + env
./scripts/add-site.sh 5 site5.yourdomain.com 8085    # with custom domain and port

# Full reset
./scripts/clean.sh                  # remove containers, volumes, network
./scripts/clean.sh --reset-env      # also reset docker/.env to .env.example
```

## Architecture

```
Cloudflare CDN → Nginx Gateway → Docker WordPress containers (1 per site)
                                     ↓
                               MariaDB + Redis (shared)
```

- **Layers**: Edge (Cloudflare) → Gateway (Nginx) → Runtime (Docker) → Application (WordPress) → Data (MariaDB) + Cache (Redis)
- **Network model**: All containers join a single external Docker network (`WORDPRESS_NETWORK` from `.env`, default `wordpress-network`). Containers reference each other by name (`wp-mariadb:3306`, `wp-redis`).
- **Site isolation**: Each WordPress site is an independent container with its own `docker-compose.yml`, its own database and DB user, and its own `wp-content` volume. Ports are assigned linearly (site N → 8080+N by convention).
- **Entry point**: Nginx `server_name`-based virtual hosting routes to `127.0.0.1:<port>`. The nginx configs in this repo are templates to be copied to a gateway server.

## Script library pattern

`scripts/lib/compose.sh` is sourced by all scripts. It provides:
- `init_compose_cmd()` — detects Docker Compose V2 (`docker compose` preferred, `docker-compose v2` as fallback), stores result in `COMPOSE_CMD` array
- `compose_cmd()` — thin wrapper that invokes the detected command

All other scripts call `init_compose_cmd` once, then use `compose_cmd` for all Compose operations. When adding new scripts, follow this pattern rather than calling `docker compose` directly.

## Critical conventions

### `$$_SERVER` in docker-compose YAML

In `docker-compose.yml` files, PHP superglobal references in `WORDPRESS_CONFIG_EXTRA` must be written as `$$_SERVER` (double dollar sign) — never `$_SERVER`. Docker Compose interprets `$` as variable interpolation; `$$` escapes it so the literal `$_SERVER` reaches PHP. Write `$$_SERVER['HTTP_X_FORWARDED_PROTO']`, not `$_SERVER['HTTP_X_FORWARDED_PROTO']`.

### .env management

- `docker/.env` contains secrets and is in `.gitignore` — never commit it
- `docker/.env.example` is the tracked template with `TODO_` placeholder values
- All Compose files use `env_file: - ../.env` relative to their location under `docker/<service>/`
- When changing `.env`, use `recreate` (not `restart`) to pick up new environment variables: `./scripts/site.sh <N> recreate`

### `add-site.sh` side effects

This script writes to four locations:
1. `docker/wp-siteN/docker-compose.yml` (generated)
2. `nginx/siteN.conf` (generated)
3. `docker/.env` (appends new `MARIADB_SITEN_*` + `WP_SITEN_PORT` vars)
4. `docker/.env.example` (same appends)

If any of these already exist, the script errors out. It also attempts to create the DB/user in MariaDB and start the container if core services are running.

### WordPress healthcheck

All site containers use `php -v` as their healthcheck — this verifies PHP is alive but does not actually test WordPress. Container "healthy" status means the PHP runtime is responsive, not that WordPress itself is installed or configured.

### init script idempotency

`docker/mariadb/init/01-init-multi-site.sh` runs only on first MariaDB start (via `docker-entrypoint-initdb.d`). It uses `IF NOT EXISTS` for databases and users. Sites added after initial deployment get their DB created by `add-site.sh` via `docker exec`.

### `--project-name` / COMPOSE_PROJECT_NAME

Every site gets an independent Docker Compose project name (`wp-siteN`) to ensure container, volume, and network name isolation. This is enforced at two levels:

1. **`docker-compose.yml`** — the top-level `name:` field declares the project name (e.g., `name: wp-site1`)
2. **Script invocation** — all site-facing scripts pass `--project-name` explicitly to `compose_cmd`:
   - `site.sh` uses `--project-name "wp-site${SITE_NO}"`
   - `up-sites.sh`, `down-all.sh`, `clean.sh`, `status.sh` derive the project name from the compose file's parent directory name (`basename "$(dirname "$compose_file")"`)
   - `add-site.sh` uses `--project-name "${SITE_NAME}"`

The `--project-name` flag takes highest priority in Docker Compose, overriding any `COMPOSE_PROJECT_NAME` env var or the `name:` field. When writing new scripts that operate on sites, always pass `--project-name` to `compose_cmd`.
