# Docker + WordPress Deployment Architecture

## 1 Project Overview

本项目提供一套 **标准化 Docker + WordPress 多站点部署架构**。

架构目标：

* 支持 **多个 WordPress 网站**
* 使用 **Docker 容器隔离**
* 通过 **Nginx Gateway 统一入口**
* 使用 **Cloudflare CDN + SSL**
* 提供 **高可维护性与可扩展性**

适用于：

```
WordPress Hosting
多站点部署
SaaS建站平台
开发环境
```

---

# 2 Architecture Overview

系统整体架构：

```
Users
  │
  │ HTTPS
  ▼
Cloudflare CDN + SSL
  │
  ▼
Server
  │
  ▼
Nginx Gateway
  │
  ▼
Docker Network
  │
  ├── WordPress Site 1
  ├── WordPress Site 2
  ├── WordPress Site 3
  │
  ▼
MariaDB Database
  │
  ▼
Redis Cache
```

架构分层：

| Layer       | Component  |
| ----------- | ---------- |
| Edge        | Cloudflare |
| Gateway     | Nginx      |
| Runtime     | Docker     |
| Application | WordPress  |
| Database    | MariaDB    |
| Cache       | Redis      |

---

# 3 Core Components

## 3.1 Cloudflare

使用 Cloudflare 提供：

* DNS
* CDN
* SSL
* WAF
* DDoS 防护

SSL 模式推荐：

```
Full (Strict)
```

---

## 3.2 Nginx Gateway

Nginx 作为统一入口网关。

主要功能：

```
域名路由
反向代理
访问日志
缓存
```

示例配置：

```nginx
server {

    listen 80;

    server_name example.com;

    location / {

        proxy_pass http://127.0.0.1:8081;

        proxy_set_header Host $host;

        proxy_set_header X-Real-IP $remote_addr;

        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    }

}
```

---

# 4 Docker Infrastructure

## 4.1 Docker Network

创建统一网络：

```bash
docker network create wordpress-network
```

所有服务都运行在该网络中：

```
wordpress containers
mariadb
redis
```

---

## 4.2 WordPress Container

每个网站运行在 **独立容器**：

```
1 website = 1 wordpress container
```

优势：

```
隔离
安全
易扩展
```

示例 docker-compose：

```yaml
version: "3.9"

services:

  wordpress:

    image: wordpress:php8.3-apache

    restart: always

    ports:

      - "8081:80"

    environment:

      WORDPRESS_DB_HOST: mariadb

      WORDPRESS_DB_USER: wp

      WORDPRESS_DB_PASSWORD: password

      WORDPRESS_DB_NAME: wordpress

    networks:

      - wordpress-network

networks:

  wordpress-network:
    external: true
```

---

# 5 Database Layer

数据库使用：

MariaDB

部署方式：

```
独立数据库容器
```

docker-compose：

```yaml
services:

  mariadb:

    image: mariadb:10.11

    restart: always

    environment:

      MYSQL_ROOT_PASSWORD: rootpass

    volumes:

      - db_data:/var/lib/mysql

    networks:

      - wordpress-network

volumes:

  db_data:
```

---

# 6 Cache Layer

缓存使用：

Redis

作用：

```
WordPress object cache
session cache
```

docker-compose：

```yaml
services:

 redis:

  image: redis:7

  restart: always

  networks:

   - wordpress-network
```

WordPress 推荐插件：

```
Redis Object Cache
```

---

# 7 Project Directory Structure

推荐目录结构：

```
/www

 ├── docker
 │   ├── mariadb
 │   │   └── docker-compose.yml
 │   │
 │   ├── redis
 │   │   └── docker-compose.yml
 │   │
 │   ├── wp-site1
 │   │   └── docker-compose.yml
 │   │
 │   ├── wp-site2
 │   │   └── docker-compose.yml
 │
 ├── nginx
 │   ├── site1.conf
 │   ├── site2.conf
 │
 └── logs
```

---

# 8 Multi-Site Deployment

每个 WordPress 站点使用独立端口：

```
site1 → 8081
site2 → 8082
site3 → 8083
```

Nginx 路由：

```
site1.com → 8081
site2.com → 8082
site3.com → 8083
```

---

# 9 Deployment Workflow

标准部署流程：

```
1 创建 docker network

2 启动 mariadb

3 启动 redis

4 创建 wordpress container

5 配置 nginx 反向代理

6 配置 Cloudflare DNS
```

---

# 10 Production Optimization

建议增加以下组件：

### Object Storage

媒体文件存储：

* Amazon S3
* Cloudflare R2

存储目录：

```
wp-content/uploads
```

---

### Monitoring

推荐：

* Prometheus
* Grafana

监控：

```
CPU
Memory
Containers
Traffic
```

---

### Logging

日志系统：

```
ELK Stack
```

组件：

* Elasticsearch
* Kibana

---

# 11 Scaling Strategy

当网站规模增长：

```
>50 sites
```

推荐升级架构：

```
Cloudflare
  │
Load Balancer
  │
Kubernetes
  │
WordPress Pods
```

使用：

Kubernetes

---

# 12 Key Advantages

该架构优势：

```
简单
稳定
低成本
易维护
易扩展
```

适合：

```
WordPress hosting
SaaS建站平台
企业官网托管
```

---

# 13 Summary

最终架构：

```
Cloudflare
   │
   ▼
Nginx Gateway
   │
   ▼
Docker Network
   │
   ├── WordPress Containers
   │
   ▼
MariaDB
   │
   ▼
Redis
```

