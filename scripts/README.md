# 运维脚本说明

本目录包含 Docker WordPress 多站点的全部运维脚本，按功能模块组织。

> **前置条件**：所有脚本依赖 `docker/.env`，首次使用前请执行 `cp docker/.env.example docker/.env` 并修改其中的 `TODO_` 密码。

---

## 1. 服务启动

### `up-all.sh` — 一键启动全部服务

```bash
./scripts/up-all.sh
```

依次启动网络 → 核心服务 → 全部站点。等效于 `up-core.sh` + `up-sites.sh`。

---

### `up-core.sh` — 启动核心服务

```bash
./scripts/up-core.sh
```

启动 MariaDB + Redis。站点依赖这两个服务，通常先启动核心再启动站点。

---

### `up-sites.sh` — 启动全部站点

```bash
./scripts/up-sites.sh
```

自动发现 `docker/wp-site*/docker-compose.yml` 并依次启动。

---

### `init-network.sh` — 初始化 Docker 网络

```bash
./scripts/init-network.sh
```

创建 `WORDPRESS_NETWORK`（默认 `wordpress-network`），已存在则跳过。通常由 `up-core.sh` 自动调用，无需手动执行。

---

## 2. 服务停止 / 清理

### `down-all.sh` — 停止全部服务

```bash
./scripts/down-all.sh
```

按顺序停止站点 → Redis → MariaDB。不删除数据卷。

---

### `clean.sh` — 清理环境（危险操作）

```bash
./scripts/clean.sh                # 删除容器 + 数据卷 + 网络
./scripts/clean.sh --reset-env    # 同时重置 docker/.env 为 .env.example
```

停止并删除全部容器和数据卷，清空数据库与缓存数据。执行后可重新 `up-all.sh` 回到初始化状态。

---

## 3. 单站点运维

### `site.sh` — 单站点精细操作

```bash
./scripts/site.sh <site_number> <action> [args]
```

| action | 说明 |
|--------|------|
| `up` | 启动站点 |
| `restart` | 重启容器进程（**不加载新环境变量**） |
| `recreate` | 强制重建容器（**加载新 .env 变量**） |
| `stop` | 停止站点容器 |
| `down` | 停止并删除站点容器 |
| `ps` | 查看站点容器状态 |
| `logs [tail]` | 查看站点日志（默认 100 行） |

```bash
# 示例
./scripts/site.sh 3 up
./scripts/site.sh 3 restart
./scripts/site.sh 3 recreate
./scripts/site.sh 3 logs 200
```

> **注意**：修改 `docker/.env` 后，`restart` 不会加载新变量，必须使用 `recreate`。

---

## 4. 站点扩展

### `add-site.sh` — 新增站点

```bash
./scripts/add-site.sh <site_number> [domain] [port]
```

自动生成：
- `docker/wp-siteN/docker-compose.yml`
- `nginx/siteN.conf`
- `docker/.env` 和 `docker/.env.example` 中对应的站点变量

若核心服务已运行，还会自动创建 MariaDB 数据库和用户并启动新站点。

```bash
# 示例
./scripts/add-site.sh 4                                # 默认域名 site4.example.com，端口 8084
./scripts/add-site.sh 5 site5.yourdomain.com 8085      # 自定义域名和端口
```

---

## 5. 状态查看

### `status.sh` — 查看全部服务状态

```bash
./scripts/status.sh
```

依次输出 MariaDB、Redis 和全部站点的容器状态。

---

## 6. 备份

备份文件存储在 `backups/` 目录，命名格式：`siteN_db_YYYYMMDD_HHMMSS.sql.gz`。

### `backup-db.sh` — 单站点数据库备份

```bash
./scripts/backup-db.sh <site_number> [--no-retention]
```

从 `wp-mariadb` 容器执行 `mariadb-dump`，输出 gzip 压缩文件。

```bash
./scripts/backup-db.sh 1               # 备份站点1
./scripts/backup-db.sh 3 --no-retention # 跳过过期清理
```

---

### `backup-db-all.sh` — 全量批量备份

```bash
./scripts/backup-db-all.sh [--no-retention]
```

自动发现 `docker/.env` 中所有站点，逐一备份 **数据库** + **wp-content**（上传文件/插件/主题）。

```bash
./scripts/backup-db-all.sh              # 备份全部站点
./scripts/backup-db-all.sh --no-retention
```

---

### 保留策略

默认执行 7/30/180 天保留策略：

| 时间段 | 规则 |
|--------|------|
| 0～7 天 | 每日备份全部保留 |
| 8～30 天 | 每周保留一份 |
| 31～180 天 | 每月保留一份 |
| >180 天 | 自动删除 |

---

## 7. 恢复

恢复需输入 `YES` 确认（`-f` 跳过），支持 `--dry-run` 预览。

### `restore-db.sh` — 恢复数据库

```bash
./scripts/restore-db.sh <site_number>                  # 自动选最新备份
./scripts/restore-db.sh <site_number> <backup_file>    # 指定备份文件
./scripts/restore-db.sh --list [siteN]                  # 列出备份
```

选项：`-f` / `--force` 跳过确认，`--dry-run` 预览操作。

```bash
./scripts/restore-db.sh 1
./scripts/restore-db.sh 1 backups/site1_db_20250624_120000.sql.gz
./scripts/restore-db.sh --list site1
./scripts/restore-db.sh 1 -f                           # 跳过确认
```

---

### `restore-content.sh` — 恢复 wp-content

```bash
./scripts/restore-content.sh <site_number>                 # 自动选最新备份
./scripts/restore-content.sh <site_number> <backup_file>   # 指定备份文件
```

恢复前自动备份当前 wp-content 到 `backups/`（带 `_pre-restore_` 后缀），防止误操作。

```bash
./scripts/restore-content.sh 1
./scripts/restore-content.sh 1 backups/site1_wp-content_20250624_120000.tar.gz
```

---

### `restore-all.sh` — 完整站点恢复

```bash
./scripts/restore-all.sh <site_number>                # 自动选最新（DB + wp-content）
./scripts/restore-all.sh <site_number> <timestamp>    # 恢复到指定时间点
```

选项：`--db-only`、`--content-only`、`-f`、`--dry-run`。

```bash
./scripts/restore-all.sh 1                                    # 完整恢复
./scripts/restore-all.sh 1 20250624_120000                    # 指定时间点
./scripts/restore-all.sh 1 --db-only -f                       # 仅DB，不确认
./scripts/restore-all.sh 1 --content-only --dry-run           # 预览文件恢复
```

---

## 脚本速查表

| 操作 | 命令 |
|------|------|
| 首次初始化 | `cp docker/.env.example docker/.env` → 修改密码 → `./scripts/up-all.sh` |
| 启动全部 | `./scripts/up-all.sh` |
| 启动核心 | `./scripts/up-core.sh` |
| 启动全部站点 | `./scripts/up-sites.sh` |
| 启动单站点 | `./scripts/site.sh 3 up` |
| 重载 .env | `./scripts/site.sh 3 recreate` |
| 查看日志 | `./scripts/site.sh 3 logs 200` |
| 查看状态 | `./scripts/status.sh` |
| 停止全部 | `./scripts/down-all.sh` |
| 新增站点 | `./scripts/add-site.sh 4 domain.com 8084` |
| 备份单站 | `./scripts/backup-db.sh 1` |
| 备份全量 | `./scripts/backup-db-all.sh` |
| 查看备份 | `./scripts/restore-db.sh --list` |
| 恢复 DB | `./scripts/restore-db.sh 1` |
| 恢复文件 | `./scripts/restore-content.sh 1` |
| 恢复全部 | `./scripts/restore-all.sh 1` |
| 环境重置 | `./scripts/clean.sh` |
