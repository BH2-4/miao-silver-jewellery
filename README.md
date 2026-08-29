# Miao Silver Jewellery — 贵州苗银外贸独立站

面向海外市场的贵州苗族银饰（Miao Silver）品牌独立站，基于 **Spree Commerce 5.6.1（headless）** 构建。

- 正式域名：`randomplayx.com`（店面）+ `api.randomplayx.com`（商业后台），DNS 托管于 Cloudflare
- 架构：Rails 8.1 API 后端（Spree 5.6，含管理后台）+ Next.js 店面（Phase 2 引入）
- 部署：后端 Render（`render.yaml` 蓝图 + `backend/Dockerfile`），店面 Vercel —— 完整流程见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)

## 仓库布局

```
backend/              # Rails 8 + Spree 5.6.1 后端：Store API /api/v3 + 管理后台
docker-compose.yml    # 本地开发：PostgreSQL 16 + Rails（容器化，与生产一致）
render.yaml           # Render 基础设施蓝图（Web 服务 + 托管 Postgres）
script/               # 辅助脚本（gem 离线下载等）
docs/                 # 部署与运维文档
```

## 快速开始（本地开发）

依赖：Docker（含 Compose）。本机无需安装 Ruby。

```bash
# 1. 准备离线 gem 缓存（国内网络推荐；数据通畅可跳过直接 compose up）
./script/download-gems.sh backend/Gemfile.lock backend/vendor/cache
#    首次安装依赖：
cd backend && docker compose run --rm web bundle install --local && cd ..

# 2. 启动数据库 + 后端（http://localhost:3000）
docker compose up

# 3. 初始化数据库（首次；另开终端）
cd backend && docker compose run --rm web bash -c \
  "bin/rails db:prepare && bin/rails db:seed AUTO_ACCEPT=1 ADMIN_EMAIL=admin@randomplayx.com ADMIN_PASSWORD=<本地密码>"
#    演示数据（可选）：bin/rails spree:load_sample_data
```

验证：

```bash
curl -s http://localhost:3000/up                              # → 200
KEY=$(docker exec miao-pg psql -U arco -d miao_silver_jewellery -tAc \
  "SELECT token FROM spree_api_keys WHERE key_type='publishable' LIMIT 1")
curl -s -H "X-Spree-Api-Key: $KEY" http://localhost:3000/api/v3/store/products | head
```

## 发布

`git push` 到 `main`：`backend/**` 变更自动触发 Render 构建（蓝图定义于 `render.yaml`）；`storefront/**`（Phase 2）变更触发 Vercel。回滚、域名绑定、开站合规清单见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)。

## 技术约束

- Ruby 4.0（`backend/.ruby-version`）；Spree 5.6.1 锁定于 `backend/Gemfile`（要求 rails >= 7.2, < 8.2）
- 依赖解析产物 `backend/Gemfile.lock` 必须提交；本机网络受限时可用 `.github/workflows/lockfile.yml`（CI）重新解析
- `config/master.key`、`.env*`、`vendor/{bundle,cache}` 绝不入库；生产密钥在 Render 环境变量配置
- `render.yaml` 不可变字段：数据库 region、PG 大版本创建后不可改
