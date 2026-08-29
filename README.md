# Miao Silver Jewellery — 贵州苗银外贸独立站

面向海外市场的贵州苗族银饰（Miao Silver）品牌独立站，基于 **Spree Commerce 5.6（headless）** 构建。

- 正式域名：`randomplayx.com`（店面）+ `api.randomplayx.com`（商业后台），DNS 托管于 Cloudflare
- 架构：Rails 8 API 后端（Spree 5.6，含 `/admin` 管理仪表盘）+ Next.js 店面（Phase 2 引入）
- 部署：后端 Render（`render.yaml` 蓝图驱动），店面 Vercel —— 完整流程见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)

## 仓库布局

```
backend/            # Rails 8 + Spree 5.6.1 后端：Store API /api/v3 + 管理后台 /admin
storefront/         # Next.js 店面（Phase 2，基于官方 spree-nextjs-storefront）
docs/               # 部署与运维文档
render.yaml         # Render 基础设施蓝图（Web 服务 + 托管 Postgres）
```

## 快速开始（后端）

```bash
# 开发数据库（本机 5433 端口）
docker run -d --name miao-pg -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_USER=arco -p 127.0.0.1:5433:5432 postgres:16-alpine

cd backend
bundle install
bin/rails db:prepare
bin/dev        # http://localhost:3000，后台在 /admin
```

创建管理员：`bin/rails db:seed ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=<强密码>`

## 发布

`git push` 到 `main`：`backend/**` 变更自动部署 Render；`storefront/**` 变更自动部署 Vercel。回滚、域名绑定、开站合规清单见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)。

## 技术约束

- Ruby 版本以 `backend/.ruby-version` 为准（Spree 5.6 要求 ≥ 3.2）
- `config/master.key`、`.env*` 绝不入库；生产密钥在 Render/Vercel 环境变量配置
- 基础设施改动（`render.yaml`）注意不可变字段：数据库 region、PG 大版本创建后不可改
