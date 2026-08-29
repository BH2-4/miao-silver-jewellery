# Miao Silver Jewellery — 贵州苗银外贸独立站

面向海外市场的贵州苗族银饰（Miao Silver）品牌独立站，基于 **Spree Commerce 5.6.1（headless）** 构建。

- **后端已上线（试跑）**：https://miao-backend-gecb.onrender.com（Render 免费档，15 分钟无流量会休眠）
- 规划域名：`randomplayx.com`（店面，Phase 2）+ `api.randomplayx.com`（后端，待绑定），DNS 托管于 Cloudflare
- 架构：Rails 8.1 API 后端（Spree 5.6.1）+ Next.js 店面（Phase 2）；后端 GHCR 镜像部署于 Render，店面将部署于 Vercel
- 完整部署与运维手册：[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)（含发布流程、种子/重建、回滚、免费档限制与升级路径）

## 仓库布局

```
backend/                  # Rails 8 + Spree 5.6.1：Store API /api/v3 + Admin API
backend/Dockerfile.seed   # 一次性种子镜像（免费档库内网执行 db:seed 用）
docker-compose.yml        # 本地开发：PostgreSQL 16 + Rails（容器化，与生产一致）
render.yaml               # Render 部署现状记录（实际经 API 创建，未走 Blueprint）
script/                   # 辅助脚本（gem 离线下载等）
.github/workflows/        # CI：镜像构建推送（docker-publish）、lockfile 解析、种子
docs/                     # 部署与运维文档
```

## 快速开始（本地开发）

依赖：Docker。国内网络先跑 `./script/download-gems.sh backend/Gemfile.lock backend/vendor/cache` 备离线缓存。

```bash
cd backend && docker compose run --rm web bundle install --local && cd ..
docker compose up                                        # PG :5433 + Rails :3000
cd backend && docker compose run --rm web bash -c \
  "bin/rails db:prepare && bin/rails db:seed AUTO_ACCEPT=1 ADMIN_EMAIL=admin@randomplayx.com ADMIN_PASSWORD=<本地密码>"
```

验证：`curl localhost:3000/up` → 200。

## 发布新代码

```bash
git push origin main     # Actions 自动构建镜像（:latest/:sha/:seed）
# 等构建全绿后触发 Render 部署（镜像部署不自动上线）：
curl -X POST -H "Authorization: Bearer $RENDER_API_KEY" -H "Content-Type: application/json" \
  -d '{}' https://api.render.com/v1/services/<SERVICE_ID>/deploys
```

回滚、数据库种子/重建、环境变量管理见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) §4。

## 技术约束

- Ruby 4.0（`backend/.ruby-version`）；Spree 5.6.1（要求 rails >= 7.2, < 8.2，锁死 5.6.1）
- `Gemfile.lock` 必须提交；本机网络受限时推 `backend/Gemfile` 由 CI（lockfile.yml）重新解析
- `config/master.key`、`.env*`、连接串、`vendor/{bundle,cache}` 绝不入库
- 生产数据库为免费档：**2026-09-28 到期删除**、无外部访问、无备份——只放试跑数据
