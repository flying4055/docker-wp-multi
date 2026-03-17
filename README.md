# Docker + WordPress 多站点部署（已初始化）

本项目已根据 `ARCHITECTURE.md` 完成第一阶段脚手架搭建，包含：

- Nginx Gateway 站点反向代理配置
- MariaDB 独立容器
- Redis 独立容器
- 3 个独立 WordPress 容器（站点隔离）
- 统一 Docker Network
- 一键启动/停止脚本

## 目录结构

```text
.
├── ARCHITECTURE.md
├── README.md
├── backups/
├── docker/
│   ├── .env.example
│   ├── mariadb/
│   │   ├── docker-compose.yml
│   │   └── init/01-init-multi-site.sh
│   ├── redis/docker-compose.yml
│   ├── wp-site1/docker-compose.yml
│   ├── wp-site2/docker-compose.yml
│   └── wp-site3/docker-compose.yml
├── logs/
├── nginx/
│   ├── site1.conf
│   ├── site2.conf
│   └── site3.conf
└── scripts/
    ├── add-site.sh
    ├── clean.sh
    ├── down-all.sh
    ├── init-network.sh
    ├── lib/compose.sh
    ├── site.sh
    ├── status.sh
    ├── up-all.sh
    ├── up-core.sh
    └── up-sites.sh
```

> 兼容性：脚本已适配 Docker 26 + Compose V2，支持 `docker compose` 与 `docker-compose v2` 自动识别。

## 快速开始

### 1) 准备环境变量

```bash
cp docker/.env.example docker/.env
# 然后编辑 docker/.env，把 TODO_ 开头密码改掉
```

### 2) 启动全部服务

```bash
./scripts/up-all.sh
```

### 3) 本地访问

- Site1: `http://127.0.0.1:8081`
- Site2: `http://127.0.0.1:8082`
- Site3: `http://127.0.0.1:8083`

### 4) 查看状态

```bash
./scripts/status.sh
```

### 5) 停止服务

```bash
./scripts/down-all.sh
```

### 6) 清理为干净环境（重置初始化数据）

```bash
./scripts/clean.sh
```

## 新增站点命令

```bash
# 自动创建 wp-site4 + nginx/site4.conf + .env 变量 + DB 用户
./scripts/add-site.sh 4

# 指定域名和端口
./scripts/add-site.sh 5 site5.yourdomain.com 8085
```

执行后会自动生成：

- `docker/wp-siteN/docker-compose.yml`
- `nginx/siteN.conf`
- `docker/.env` / `docker/.env.example` 里对应站点变量

若核心服务已启动，会自动创建 MariaDB 数据库与用户并尝试启动新站点容器。

## 运维操作说明

### 模块 A：单个站点操作（精细化，不影响其他站点）

使用短命令脚本（以站点 `3` 为例）：

```bash
# 启动/拉起
./scripts/site.sh 3 up

# 快速重启
./scripts/site.sh 3 restart

# .env 改动后重建（加载新变量）
./scripts/site.sh 3 recreate

# 查看状态 / 日志
./scripts/site.sh 3 ps
./scripts/site.sh 3 logs 200
```

修改 `docker/.env` 后，通常不需要重启全部容器：

- 只改某站点变量（如 `SITE3_*`）→ 只重建该站点容器
- 只改 MariaDB/Redis 变量 → 只重建对应核心服务（必要时再重建依赖站点）

> 注意：`restart` 不会加载新的容器环境变量；请使用 `recreate`。

### 模块 B：多个站点/全量操作（批量管理）

```bash
# 启动核心服务（MariaDB + Redis）
./scripts/up-core.sh

# 启动全部站点（wp-site*）
./scripts/up-sites.sh

# 一键启动全部（核心 + 站点）
./scripts/up-all.sh

# 查看全部服务状态
./scripts/status.sh

# 停止全部服务
./scripts/down-all.sh

# 清理初始化数据（容器/数据卷/网络）
./scripts/clean.sh
```

新增站点后也不需要全量重启，推荐按单站点增量处理：

```bash
# 创建站点（核心服务运行时会自动尝试启动）
./scripts/add-site.sh 4 site4.yourdomain.com 8084

# 若该站点未启动，执行：
./scripts/site.sh 4 up

# 重载 Nginx
nginx -t && nginx -s reload
```

如需彻底回到“未初始化”状态：

```bash
# 清理容器 + 数据卷 + 网络
./scripts/clean.sh

# 同时重置 docker/.env（可选）
./scripts/clean.sh --reset-env
```

## Nginx + Cloudflare 接入

1. 将 `nginx/site1.conf` ~ `site3.conf` 拷贝到网关服务器 Nginx 配置目录。
2. 修改 `server_name` 为真实域名。
3. 在 Cloudflare 添加 DNS 记录指向网关服务器。
4. Cloudflare SSL 模式使用 `Full (Strict)`。

## 生产建议（下一阶段）

- 增加自动备份脚本（DB + wp-content，7/30/180 保留）
- 增加监控告警（Prometheus + Grafana）
- 增加日志聚合（ELK 或 Loki）
- 增加 CI/CD（镜像构建、分环境发布、可回滚）
