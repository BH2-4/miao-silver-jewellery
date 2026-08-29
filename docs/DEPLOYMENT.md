# 正式部署文档 · randomplayx.com

> 仓库：`miao-silver-jewellery` ｜ 用途：贵州苗银外贸独立站 ｜ 基础框架：Spree Commerce 5.6.1（headless）
> 最后更新：2026-08-29（后端已在 Render 免费档上线，本文档与实际部署对齐）

## 0. 当前部署状态（2026-08-29 实测）

| 项 | 状态 | 说明 |
|---|---|---|
| 后端服务 miao-backend | ✅ live | https://miao-backend-gecb.onrender.com（`/up` 200） |
| 数据库 miao-db（PG16 free） | ✅ available | 176 迁移全部就位；**2026-09-28 到期**（30 天限制） |
| 店铺种子 + 管理员 | ✅ 已验证 | admin 登录 API 返回 200 + JWT |
| 镜像流水线 | ✅ 全绿 | `ghcr.io/bh2-4/miao-backend`（`latest` / `<git-sha>` / `seed` 三个标签） |
| api.randomplayx.com 绑定 | ⬜ 未做 | 见 §5 |
| Next.js 店面（Vercel） | ⬜ Phase 2 | 见 §6 |
| 支付接入 | ⬜ 未开始 | 见 §7 |

已修复并沉淀的三个部署期问题（防复发）：

1. **database.yml 覆盖连接串**：production 段必须整段 `url: <%= ENV["DATABASE_URL"] %>`，不得残留 username/database 显式键（Rails 合并规则：YAML 显式键优先于 URL 成分）
2. **csv 常量缺失**：Ruby 3.4+ 移除标准库 csv，spree_core 依赖却未声明且不自动加载 → `config/application.rb` 顶部 `require "csv"`
3. **免费档 Postgres 无外部访问**：Render free 数据库只能从 Render 内网连（本机/GitHub Actions 一律 SSL 拒绝）→ 一切 DB 操作必须走"内网执行"（见 §4.4）

## 1. 架构总览

```
                Cloudflare DNS（randomplayx.com 托管区）
                 │                          │
    randomplayx.com（apex+www）    api.randomplayx.com（未绑定）
                 │                          │
          ┌──────▼──────┐           ┌──────▼──────────────┐
          │   Vercel    │  REST API │    Render（镜像）    │
          │  Next.js    │──────────▶│  Rails 8 + Spree    │
          │  店面(SEO)  │  /api/v3  │   免费档·会休眠     │
          │  （Phase2） │           └─────────┬───────────┘
          └─────────────┘                     │ 内网连接
                                    ┌────────▼────────┐
                                    │ Render Postgres │
                                    │  free·30天到期  │
                                    └─────────────────┘
```

| 组件 | 技术 | 承载 | 部署位置 |
|---|---|---|---|
| 顾客店面 | Next.js（`storefront/`，Phase 2） | 商品浏览、SEO、结账 | Vercel（Hobby 免费档） |
| 商业后台 | Rails 8 + Spree 5.6.1（`backend/`） | Store API `/api/v3`、Admin API | Render（GHCR 镜像，free 档） |
| 数据库 | PostgreSQL 16 | 商品、订单、用户 | Render 托管 Postgres（free） |
| 图片存储 | Active Storage | 产品图（当前本地磁盘，随容器重建丢失） | 接单前迁 S3/R2 |

## 2. 仓库布局

```
backend/                  # Rails 8 + Spree 5.6.1：Dockerfile、Dockerfile.seed、全部应用代码
docs/DEPLOYMENT.md        # 本文档
render.yaml               # Render 现状记录（实际经 API 创建，未走 Blueprint）
docker-compose.yml        # 本地开发：PG16(:5433) + Rails(:3000)
script/download-gems.sh   # 国内网络离线下载 lockfile 全量 gem
.github/workflows/
  docker-publish.yml      # 构建并推送 :latest / :sha / :seed 镜像（push main 触发）
  seed.yml                # 手动触发：从外部对库执行 db:seed（⚠️ free 档库不可达，仅付费库可用）
  lockfile.yml            # Gemfile 变更时由 CI 重新解析 Gemfile.lock
```

## 3. 本地开发（backend/，容器化）

前置：仅 Docker。本机无需 Ruby——开发与生产同为容器。

```bash
# 国内网络先备离线 gem 缓存
./script/download-gems.sh backend/Gemfile.lock backend/vendor/cache
cd backend && docker compose run --rm web bundle install --local && cd ..

docker compose up          # PG :5433 + Rails :3000

# 首次初始化（本地库）
cd backend && docker compose run --rm web bash -c \
  "bin/rails db:prepare && bin/rails db:seed AUTO_ACCEPT=1 ADMIN_EMAIL=admin@randomplayx.com ADMIN_PASSWORD=<本地密码>"
bin/rails spree:load_sample_data   # 演示数据（可选）
```

验证：`curl http://localhost:3000/up` → 200；带 `X-Spree-Api-Key`（取自 `spree_api_keys` 表）访问 `/api/v3/store/products`。

## 4. 后端部署与运维（Render，镜像方案）

### 4.1 为什么是镜像部署

- 本工作区的 Render-GitHub 集成无法访问本仓库（`unfetchable`，多轮验证未解），Git-backed 与 Blueprint 流程不可用
- 镜像方案：GitHub Actions（数据中心网络）构建 → GHCR 公开镜像 → Render 以 `runtime: image` 拉取
- 代价：镜像更新**不自动部署**（`autoDeployTrigger: off`），需手动触发（§4.2）；GHCR 包当前为公开（试跑期接受，正式期改私有 + registryCredential）

### 4.2 发布新代码（标准流程）

```bash
git push origin main
# 等 Actions docker-publish.yml 全绿（首次~4min，缓存后~1.5min）
# 触发部署（重新拉取 :latest）：
curl -s -X POST -H "Authorization: Bearer $RENDER_API_KEY" \
  -H "Content-Type: application/json" -d '{}' \
  https://api.render.com/v1/services/<SERVICE_ID>/deploys
```

监控：

```bash
render logs --resources <SERVICE_ID> --limit 50 --output text --confirm   # 应用日志
# 部署状态：GET /v1/services/<SERVICE_ID>/deploys/<DEPLOY_ID>，live 即成功
```

服务 ID 见 `render.yaml` 注释或 Dashboard；本机 CLI 需先 `render workspace set tea-da38g3lg1s2s73d235eg`。

### 4.3 环境变量管理

线上生效清单（值一律不进仓库）：

| 键 | 值来源 | 说明 |
|---|---|---|
| `DATABASE_URL` | miao-db **内部**连接串 | 经 `GET /v1/postgres/<DB_ID>/connection-info` 取 `internalConnectionString`，PUT env-vars 写入 |
| `RAILS_MASTER_KEY` | `backend/config/master.key` | 泄露即轮换：重新 `rails credentials` 体系 |
| `RAILS_ENV/RAILS_LOG_LEVEL/RAILS_STORAGE_SERVICE/WEB_CONCURRENCY/RAILS_MAX_THREADS` | 固定值 | 见 render.yaml |

注意：env-vars 的 PUT 是**全量替换**语义——先 GET 现有列表、变更后整体 PUT 回去。历史教训：创建后新写入的变量到容器生效可能有延迟，部署失败先复查容器实际 env 再排查其他。

### 4.4 数据库初始化/重种子（免费档内网执行法）

免费档库不可外部连接，SSH 又被 CLI 锁交互模式——采用**一次性种子服务**：

1. `:seed` 镜像已由流水线自动构建（基于主镜像，CMD 固化为 `bin/rails db:seed`）
2. 创建一次性 free web 服务（image `:seed` + 内部连接串 + `AUTO_ACCEPT/ADMIN_EMAIL/ADMIN_PASSWORD` 环境变量）
3. 任务跑完进程自然退出 → Render 标记 deploy failed（**预期现象，非故障**）→ 查日志确认种子输出
4. **立即删除该服务**（省免费时长）
5. 验证：`POST /api/v3/admin/auth/login` 凭管理员账号应返回 200 + JWT

重建数据库（到期/换库）：删旧库建新库 → 改服务 `DATABASE_URL` → 触发一次部署（入口脚本自动 db:prepare 全量迁移）→ 执行上述种子流程。全程约 10 分钟。

### 4.5 回滚

```bash
# 部署任意历史版本（每次构建都有 :<git-sha> 标签）：
curl -s -X POST ... -d '{"imageUrl": "ghcr.io/bh2-4/miao-backend:<旧sha>"}' \
  https://api.render.com/v1/services/<SERVICE_ID>/deploys
```

注意：代码回滚不回滚数据库 schema；当前库仅结构无业务数据，最坏整库重建（§4.4）。

### 4.6 免费档限制与升级路径

| 限制 | 影响 | 升级动作（需在 Render 绑卡） |
|---|---|---|
| 服务 15 分钟无流量休眠 | 冷启动 30-60s | web → starter（$7/月，不休眠） |
| 750 免费时长/月·全工作区 | 仅够一个常驻服务（旧 5 服务已挂起腾位） | 升级后旧服务可按需恢复 |
| Postgres 30 天过期（**9-28**） | 到期整库删除 | db → basic-256mb（$6/月，解锁外部连接 + 每日备份） |
| 无磁盘持久化 | 容器重建丢上传图片 | 接单前迁 S3/Cloudflare R2 |

## 5. 域名绑定（下一步）

1. **api.randomplayx.com**：Render Dashboard → miao-backend → Settings → Custom Domains 添加 → Cloudflare 加 CNAME（`api` → `miao-backend-gecb.onrender.com`，先灰云）→ 验证 `https://api.randomplayx.com/up` 200
2. **randomplayx.com + www**：待店面上线后绑 Vercel（§6）
3. SSL/TLS 模式 **Full (strict)**，开启 Always Use HTTPS
4. ⚠️ apex 记录生效即替换现挂旧站「Random Play X」，切换前与相关方确认

## 6. 店面（Phase 2，Vercel 免费档）

1. 引入官方 `spree/spree-nextjs-storefront` 至 `storefront/`，配 `NEXT_PUBLIC_API_URL=https://api.randomplayx.com` 与 publishable key
2. Vercel Import（Root Directory: `storefront/`）→ 绑 apex + www（www 301 → apex）
3. 每个 PR 自动预览，验收后合并
4. 说明：Vercel 只承担 Next.js 店面；Rails 后端无法跑在 Vercel（无常驻进程/不支持 Ruby 运行时），维持 Render 不变

## 7. 正式开站前清单（外贸合规与转化）

- [ ] 支付：Stripe / PayPal 开通，`randomplayx.com` 审核前政策页齐全可访问
- [ ] 政策页（店面承载）：Privacy / Terms / Return & Refund / Shipping
- [ ] 合规：对美 ≤$800/单 de minimis；原产国标识；银饰纯度如实标注（S925/S999）
- [ ] 宣传红线：不使用「保值/投资/治病」类表述
- [ ] GA4 + Search Console（apex 与 www 都验证）+ sitemap
- [ ] 品牌词 Title/Description、Product 结构化数据、OG 图
- [ ] 域名邮箱 + WhatsApp Business
- [ ] 产品图迁 S3/R2；Render PG 升级并开启每日备份
- [ ] 管理后台强密码 + 后台限 IP（Cloudflare Access/WAF）

## 8. 安全事项

- [ ] **轮换 Render API key**（曾出现在聊天记录）：Dashboard → Settings → API Keys
- [ ] **更换生产 admin 密码**（当前为开发密码）
- [ ] GHCR 包转私有 + Render 配 registryCredential（镜像含生产代码）
- [ ] `master.key`、`.env*`、连接串永不入库；GitHub secrets 现有：`RENDER_DB_URL`（外部串，free 档下已无用，可删）、`RAILS_MASTER_KEY`、`ADMIN_PASSWORD`
- [ ] free 档库到期即删——不要往里面放任何舍不得的数据

## 9. 成本概览

| 阶段 | 配置 | 月成本 |
|---|---|---|
| 试跑（当前） | Render free ×2（web+db）+ Vercel Hobby + Cloudflare Free | $0 |
| 正式接单 | Render starter + basic-256mb + Vercel Pro（商用） | ~$33 |
