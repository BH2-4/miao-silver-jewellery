# 正式部署流程 · randomplayx.com

> 仓库：`miao-silver-jewellery` ｜ 用途：贵州苗银外贸独立站 ｜ 基础框架：Spree Commerce 5.6（headless）
> 最后更新：2026-08-29

## 0. 架构总览

采用 Spree 官方主线架构（5.5+）：**Rails API 后端 + Next.js 店面**，前后端分离部署。

```
                    Cloudflare DNS（域名 randomplayx.com 托管区）
                     │                          │
        randomplayx.com（apex + www）   api.randomplayx.com
                     │                          │
              ┌──────▼──────┐           ┌──────▼──────────────┐
              │   Vercel    │  REST API │   Render (Docker)   │
              │  Next.js    │──────────▶│  Rails 8 + Spree    │
              │  店面(SEO)  │  /api/v3  │  /api/v3 + /admin   │
              └─────────────┘           └─────────┬───────────┘
                     │                            │
                用户浏览/下单            ┌────────▼────────┐
                                          │ Render Postgres │
                                          └─────────────────┘
```

| 组件 | 技术 | 承载 | 部署位置 |
|---|---|---|---|
| 顾客店面 | Next.js（`storefront/`，Phase 2 引入） | 商品浏览、SEO 落地页、结账流程 | Vercel |
| 商业后台 | Rails 8 + Spree 5.6（`backend/`） | Store API `/api/v3`、Admin API（React 仪表盘接入）、订单/库存 | Render（Docker） |
| 数据库 | PostgreSQL 16+ | 商品、订单、用户 | Render 托管 Postgres |
| 图片存储 | Active Storage | 产品图（初期本地磁盘，正式期迁 S3/Cloudflare R2） | 随后端 |

选型理由：Spree 5.5+ 官方主线已转向 headless（Rails 店面 gem `spree_storefront` 停更于 5.4.6），官方明确该架构面向跨境电商场景；Next.js 店面对 SEO 与首屏性能更友好，符合外贸独立站获客需求。Spree 5.6 已移除 Redis 与独立 worker 依赖，后端仅需一个 Web 服务 + 数据库。

> 备选：若想回到单体 Rails 店面，需锁 Spree `5.4.6` + `spree_storefront`，不享受后续更新，不推荐。

## 1. 仓库布局

```
backend/            # Rails 8 + Spree 5.6.1 后端（本仓库当前主体）
storefront/         # Next.js 店面（Phase 2，基于官方 spree-nextjs-storefront）
docs/DEPLOYMENT.md  # 本文档
render.yaml         # Render 基础设施蓝图（后端 + 数据库）
```

生产分支：`main`。后端与店面的部署互相独立：`backend/**` 变更只触发 Render，`storefront/**` 变更只触发 Vercel。

## 2. 后端本地开发（backend/，容器化）

前置：仅 Docker（含 Compose）。本机无需安装 Ruby——开发环境与生产同为容器，架构一致。

```bash
# 国内网络建议先备离线 gem 缓存（详见 README）
./script/download-gems.sh backend/Gemfile.lock backend/vendor/cache
cd backend && docker compose run --rm web bundle install --local && cd ..

# 启动（PostgreSQL 16 :5433 + Rails :3000）
docker compose up

# 首次初始化数据库 + 管理员
cd backend && docker compose run --rm web bash -c \
  "bin/rails db:prepare && bin/rails db:seed AUTO_ACCEPT=1 ADMIN_EMAIL=<邮箱> ADMIN_PASSWORD=<强密码>"
bin/rails spree:load_sample_data   # 演示数据（可选）
```

- 健康检查：`GET http://localhost:3000/up`
- Store API：`/api/v3/store/*`，请求头 `X-Spree-Api-Key: <publishable key>`（key 存于 `spree_api_keys` 表）
- 管理后台/仪表盘 API：`/api/v3/admin/*`（Spree 5.6 管理界面为 React 仪表盘，直连 Admin API）
- 测试：`docker compose run --rm web bin/rails test`
- 依赖解析：改 `Gemfile` 后本机网络不通时，推送触发 `.github/workflows/lockfile.yml` 由 CI 生成 lockfile

## 3. 后端正式部署（Render，蓝图驱动）

基础设施定义在仓库根 `render.yaml`（Web 服务 + 托管 Postgres），Render 会按蓝图自动同步。

首次开通：

1. Render Dashboard → **New → Blueprint** → 授权并选择本仓库 → Render 读取 `render.yaml` 创建 `miao-backend` 服务与 `miao-db` 数据库
2. 首次同步前，在 Dashboard 为服务补充 `sync: false` 的密钥：
   - `RAILS_MASTER_KEY`＝本地 `backend/config/master.key` 的内容（`config/credentials.yml.enc` 的解密钥匙，**绝不入库**）
3. 首次部署完成后执行一次初始化（Dashboard → Shell，或本地指生产库执行）：
   ```bash
   bin/rails db:migrate
   bin/rails db:seed ADMIN_EMAIL=<管理员邮箱> ADMIN_PASSWORD=<强密码>
   ```
4. 之后每次 `git push origin main`：Render 按 `backend/Dockerfile` 自动构建镜像 → 容器入口 `bin/docker-entrypoint` 自动执行 `db:prepare`（含迁移）→ 通过 `/up` 健康检查后切流。首次部署后补一次种子（Render Shell）：`bin/rails db:seed AUTO_ACCEPT=1 ADMIN_EMAIL=<邮箱> ADMIN_PASSWORD=<强密码>`

要点：

- 数据库连接串通过蓝图由 `DATABASE_URL`（`fromDatabase`）注入，不落明文
- `postgresMajorVersion`、`region` 创建后**不可更改**，蓝图中已按弗吉尼亚（us-east，兼顾欧美客群）+ PG16 定稿
- 回滚：Deployments → 任意历史版本 → **Rollback**；数据库迁移回滚需另跑 `db:rollback`
- 建议升级时机：`free` 实例仅用于联调（会休眠、Postgres 免费 30 天过期）；正式接单前升 `starter`+（512MB 起，Spree 建议 ≥ 1GB 内存实例）

## 4. 域名与 DNS（Cloudflare 托管区）

DNS 记录规划（`randomplayx.com` 托管在 Cloudflare，NS：felicity / mckinley.ns.cloudflare.com）：

| 类型 | 主机记录 | 记录值 | 代理 | 说明 |
|---|---|---|---|---|
| CNAME | `@` | `cname.vercel-dns.com` | 先灰云 | 店面（Vercel 分配，以导入域名后面板为准） |
| CNAME | `www` | `cname.vercel-dns.com` | 先灰云 | Vercel 侧配置 301 → apex |
| CNAME | `api` | `miao-backend.onrender.com` | 先灰云 | 后端（以 Render 服务默认域名为准） |

步骤：

1. **后端**：Render → miao-backend → Settings → Custom Domains → 添加 `api.randomplayx.com` → 按提示在 Cloudflare 加 CNAME → 等待证书签发（Render 自动签 Let's Encrypt）
2. **店面**（Phase 2）：Vercel 项目 → Settings → Domains → 添加 `randomplayx.com` 与 `www` → 按提示加 CNAME → Vercel 自动签证书
3. **验证**：`https://api.randomplayx.com/up` 返回 200；`https://randomplayx.com` 返回店面首页
4. **SSL 模式**：Cloudflare SSL/TLS 设 **Full (strict)**；始终 HTTPS 开启
5. **代理（橙云）**：初期建议 DNS-only（灰云），由各平台直接签证书最稳；后续需要 Cloudflare WAF/缓存再加橙云，加后必须保持 Full (strict) 防止重定向循环
6. ⚠️ **切换前确认**：randomplayx.com 当前仍承载旧站「Random Play X — 链接索引」，上述 apex 记录生效即替换旧站，操作前和相关同事打招呼

## 5. 店面部署（Phase 2，Vercel）

1. Fork/引入官方 `spree/spree-nextjs-storefront` 至本仓库 `storefront/`，配好后端地址 `NEXT_PUBLIC_API_URL=https://api.randomplayx.com` 与 Store API token
2. Vercel → Import Git Repository → Root Directory 选 `storefront/`（仅 `storefront/**` 触发构建）
3. 域名绑定见上节；Next.js 用默认构建（零配置）
4. 预览环境：每个 PR 自动生成 `*.vercel.app` 预览地址，验收后合并

## 6. 正式开站前清单（外贸合规与转化）

- [ ] **支付**：Stripe / PayPal 开通，提交 `randomplayx.com` 审核前确认政策页齐全且可访问
- [ ] **政策页**（店面承载）：Privacy Policy、Terms of Service、Return & Refund、Shipping Policy
- [ ] **合规申报**：对美销售 ≤ 800 USD/单走 de minimis；商品需原产国标识；如实申报材质（S925/S999 苗银含银量）
- [ ] **宣传红线**：不使用「保值/投资/治病」类表述；银饰重量与纯度如实标注
- [ ] **分析与收录**：GA4、Google Search Console 验证 apex（注意同时验证 `www`）、提交 sitemap
- [ ] **SEO 基线**：品牌词 Title/Description、Product 结构化数据、OG 图
- [ ] **联系渠道**：域名邮箱（hello@randomplayx.com）、WhatsApp Business
- [ ] **图片存储**：产品图迁 S3 或 Cloudflare R2（多实例/重建容器后本地盘数据会丢）
- [ ] **备份**：Render Postgres 开启每日自动备份（付费计划）
- [ ] **管理后台**：强密码 + 后台路径限 IP（Cloudflare Access 或 WAF 规则）

## 7. 应急与回滚

| 场景 | 动作 |
|---|---|
| 后端新版有 bug | Render Deployments → Rollback（秒级，不含数据） |
| 迁移损坏数据 | `bin/rails db:rollback STEP=1` + 从备份恢复 |
| 店面故障 | Vercel Instant Rollback；紧急时 Cloudflare 挂维护页 |
| 域名/DNS 故障 | Cloudflare 事件页；临时切 `*.onrender.com`/`*.vercel.app` 直连验证 |

## 8. 月成本概览（正式接单期）

| 项 | 方案 | 费用 |
|---|---|---|
| Render Web 服务 | starter 512MB | ~$7 |
| Render Postgres | basic-256mb 起（低量起步） | ~$6 |
| Vercel | Hobby（商用需 Pro） | $0 → $20 |
| Cloudflare | Free 计划 | $0 |

月固定成本约 $13–33；带宽超量后按量计费。
