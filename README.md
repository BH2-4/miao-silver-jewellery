# Miao Silver Jewellery — 贵州苗银外贸独立站

面向海外市场的贵州苗族银饰（Miao Silver）品牌独立站，基于 **Spree Commerce 5.6.1（headless）** 构建。

- **✅ 全链路已上线（2026-08-29，试跑）**：**randomplayx.com** = 3D 引导站（SilverForgedGui，末尾 CTA 跳店）→ **shop.randomplayx.com** = Vercel 店面（9 款 mock 苗银商品）→ https://miao-backend-gecb.onrender.com（Render 后端）→ Render Postgres（free，**2026-09-28 到期**）
- DNS：Cloudflare 托管，apex + www 已切 Vercel（灰云）；`api.` 子域待绑
- 支付暂未接入（按需求延后）；正式开站前清单见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) §8

## 仓库布局

```
backend/                  # Rails 8 + Spree 5.6.1：Store API /api/v3 + Admin API
backend/Dockerfile.seed   # 一次性种子镜像（免费档库内网执行 db:seed 用）
backend/db/seeds/
  mock_products.rb        # 9 款苗银 mock 商品（幂等；LOAD_MOCK_PRODUCTS=1 触发）
  assets/                 # 9 张产品图（烧入镜像）
backend/lib/tasks/miao_images.rake   # 图片自愈（容器重建后重挂载）
docker-compose.yml        # 本地开发：PostgreSQL 16 + Rails（容器化，与生产一致）
render.yaml               # Render 部署现状记录（实际经 API 创建，未走 Blueprint）
script/                   # 辅助脚本（gem 离线下载等）
.github/workflows/        # CI：镜像构建推送（docker-publish）、lockfile 解析、种子
docs/                     # 部署与运维文档
```

> ⚠️ Next.js 店面源码**暂不在本仓库**：备份于 `~/miao-backups/storefront-2026-08-29.tar.gz`（上游锁定 commit 见文档 §6），入库待安全扫描误报处理后完成。

## 快速开始（本地开发）

依赖：Docker。国内网络先跑 `./script/download-gems.sh backend/Gemfile.lock backend/vendor/cache` 备离线缓存。

```bash
cd backend && docker compose run --rm web bundle install --local && cd ..
docker compose up                                        # PG :5433 + Rails :3000
cd backend && docker compose run --rm web bash -c \
  "bin/rails db:prepare && bin/rails db:seed AUTO_ACCEPT=1 ADMIN_EMAIL=admin@randomplayx.com ADMIN_PASSWORD=<本地密码>"
cd backend && docker compose run --rm web bin/rails db:seed LOAD_MOCK_PRODUCTS=1   # 追加 9 款 mock 商品
```

验证：`curl localhost:3000/up` → 200；`GET /api/v3/store/products` 带 `X-Spree-Api-Key` 返回商品。

## 发布新代码

```bash
git push origin main     # Actions 自动构建镜像（:latest/:sha/:seed）
# 等构建全绿后触发 Render 部署（镜像部署不自动上线）：
curl -X POST -H "Authorization: Bearer $RENDER_API_KEY" -H "Content-Type: application/json" \
  -d '{}' https://api.render.com/v1/services/<SERVICE_ID>/deploys
```

店面（Vercel）：在店面源码目录 `vercel deploy --prod`（当前无 Git 集成）。

回滚、数据库种子/重建、环境变量管理、mock 数据与图片自愈、域名/DNS 见 [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) §4–§7。

## 技术约束

- Ruby 4.0（`backend/.ruby-version`）；Spree 5.6.1（要求 rails >= 7.2, < 8.2，锁死 5.6.1）
- `Gemfile.lock` 必须提交；本机网络受限时推 `backend/Gemfile` 由 CI（lockfile.yml）重新解析
- `config/master.key`、`.env*`、连接串、`vendor/{bundle,cache}` 绝不入库
- 商品不可见排查三道闸：`status=active` + 各 Channel 的 `ProductPublication` + 分页 25/页（文档 §5.2）
- 生产数据库为免费档：**2026-09-28 到期删除**、无外部访问、无备份——只放试跑数据
