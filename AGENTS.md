# 项目代理说明（agents.md）

本文档根据当前目录结构自动整理，供 AI/自动化代理在本仓库中执行任务时参考。

## 1. 项目概览

这是一个基于 Docker 的 WordPress 多站点部署项目，核心组件：

- 网关层：`nginx/`（3 个站点反向代理配置）
- 应用层：`docker/wp-site1|2|3/`（3 个独立 WordPress 容器）
- 数据层：`docker/mariadb/`（MariaDB）
- 缓存层：`docker/redis/`（Redis）
- 运维脚本：`scripts/`

## 2. 目录结构（扫描结果）

```text
.
├── ARCHITECTURE.md
├── README.md
├── backups/
│   └── .gitkeep
├── docker/
│   ├── .env
│   ├── .env.example
│   ├── mariadb/
│   │   ├── docker-compose.yml
│   │   └── init/01-init-multi-site.sh
│   ├── redis/docker-compose.yml
│   ├── wp-site1/docker-compose.yml
│   ├── wp-site2/docker-compose.yml
│   └── wp-site3/docker-compose.yml
├── logs/
│   └── .gitkeep
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

## 3. 推荐执行顺序

1. 准备变量：
   - `cp docker/.env.example docker/.env`
   - 修改 `docker/.env` 中所有 `TODO` 密码
2. 启动核心服务：
   - `./scripts/up-core.sh`
3. 启动站点服务：
   - `./scripts/up-sites.sh`
4. 一键启动（可替代 2+3）：
   - `./scripts/up-all.sh`
5. 查看状态：
   - `./scripts/status.sh`
6. 停止全部：
   - `./scripts/down-all.sh`
7. 清理为干净环境（可选）：
   - `./scripts/clean.sh`

## 4. 代理执行约束

- 不要提交敏感信息：`docker/.env` 必须保持本地私有。
- 修改端口/域名时需同步更新：
  - `docker/.env`
  - `nginx/site*.conf`
  - `README.md`（如涉及使用方式变化）
- 涉及 WordPress 反向代理 HTTPS 判断时，`docker-compose.yml` 内 PHP 变量必须写为 `$$_SERVER`（避免 Compose 变量插值告警）。

## 5. 常见任务入口

- 新增站点：复制 `docker/wp-site1` 结构为新站点目录，并新增对应 Nginx 配置。
- 新增站点（推荐）：`./scripts/add-site.sh <site_number> [domain] [port]`
- 单站点运维（推荐）：`./scripts/site.sh <site_number> <up|restart|recreate|ps|logs>`
- 环境重置（危险操作）：`./scripts/clean.sh [--reset-env]`
- 排查容器状态：`./scripts/status.sh` + `docker compose ... logs`
- 网关调试：检查 `nginx/site*.conf` 的 `server_name` 与 `proxy_pass` 端口映射。

## 6. 建议后续增强

- 备份自动化（DB + wp-content，7/30/180 保留策略）
- 监控与告警（Prometheus + Grafana）
- 日志聚合（ELK 或 Loki）
- CI/CD（构建、发布、回滚）
