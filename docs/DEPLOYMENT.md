# 正式部署文档 · randomplayx.com

> 仓库：`miao-silver-jewellery` ｜ 用途：贵州苗银外贸独立站 ｜ 基础框架：Spree Commerce 5.6.1（headless）
> 最后更新：2026-08-29（**全链路已上线**：Cloudflare DNS → Vercel 店面 → Render 后端 → Render PG）

## 0. 当前部署状态（2026-08-29 实测）

| 项 | 状态 | 说明 |
|---|---|---|
| 后端服务 miao-backend | ✅ live | https://miao-backend-gecb.onrender.com（`/up` 200） |
| 数据库 miao-db（PG16 free） | ✅ available | 176 迁移全部就位；**2026-09-28 到期**（30 天限制） |
| Mock 商品数据 | ✅ 9 款已上架 | 详见 §5；商品可见性三道闸全部打通 |
| 管理后台 | ✅ 可登录 | `POST /api/v3/admin/auth/login` 返回 200 + JWT |
| Next.js 店面（Vercel） | ✅ live | 项目 `miao-storefront`（Hobby 免费档），域名 **shop.randomplayx.com** |
| randomplayx.com + www | ✅ 3D 引导页 | 指向 **SilverForgedGui**（Spree 演示之外的 3D 前置引导站，github.com/BH2-4/SilverForgedGui）；末尾 CTA 按钮新标签跳 `shop.randomplayx.com`（带 UTM） |
| api.randomplayx.com 绑定 | ⬜ 未做 | 见 §7 |
| 支付接入 | ⬜ 按用户要求暂缓 | 见 §8 |

上线验证证据链（2026-08-29）：
1. DNS：apex 经 Cloudflare CNAME 扁平化解析出 Vercel anycast IP（76.76.21.98 等）；www CNAME → `cname.vercel-dns.com` ✓
2. Vercel：apex + www 均分配至项目且 `verified:true`；www 301 → apex；部署保护策略为 `all_except_custom_domains`（**自定义域名不受登录墙影响，公开可访问**）
3. Render 日志：DNS 切换后出现来自 AWS us-east（Vercel 函数区域）、`user_agent=node` 的 SSR 请求（`/api/v3/store/products?limit=8&fields=...`、`/api/v3/store/markets`、商品详情 `dragon-phoenix-silver-collar` 等），全部 200 —— 店面渲染 → 后端取数链路实证打通

⚠️ 本机网络无法直连 Vercel IP 段（TLS 握手被重置，`*.vercel.app` 与自定义域名同样症状），日常验证用：Render 日志（看 SSR 流量）、`curl https://miao-backend-gecb.onrender.com/up`、或换外部网络。

### 资源清单（ID 非机密，便于运维）

| 资源 | 标识 |
|---|---|
| Render workspace | `tea-da38g3lg1s2s73d235eg` |
| Render 后端服务 | `srv-da993hhsrm7s73bjfrk0` |
| Render Postgres（free，9-28 到期） | `dpg-da97i6ijnfac73culi00-a`（miao_db / miao_db_user） |
| Vercel 项目（店面） | `prj_zYOT73pxIqtXnhr5bSYXq6gE7Azo`（miao-storefront，shop.randomplayx.com） |
| Vercel 项目（3D 引导站） | `prj_5AFSjQnXFCxhAJj5vr9J7mQHjfbS`（silverforgedgui，randomplayx.com；源码在独立仓库 BH2-4/SilverForgedGui） |
| Cloudflare zone | `41a6e698ef8bec7aaba7d0253b76dd73` |
| Storefront publishable key（公开物，非机密） | `pk_by3q8DrnxB1uzw48DUnWrgeP` |

### 已踩坑沉淀（防复发）

1. **database.yml 覆盖连接串**：production 段必须整段 `url: <%= ENV["DATABASE_URL"] %>`，不得残留 username/database 显式键（Rails 合并规则：YAML 显式键优先于 URL 成分）
2. **csv 常量缺失**：Ruby 3.4+ 移除标准库 csv，spree_core 依赖却未声明且不自动加载 → `config/application.rb` 顶部 `require "csv"`
3. **免费档 Postgres 无外部访问**：Render free 数据库只能从 Render 内网连（本机/GitHub Actions 一律 SSL 拒绝）→ 一切 DB 操作必须走"内网执行"（§4.4）
4. **Render 环境变量传播不可靠**：API 写入的 envVars 可能长期不达容器 → 需要可靠开关时用 **rake 参数即环境变量** 的老技巧（`bin/rails db:seed LOAD_MOCK_PRODUCTS=1`），或直接烧进镜像 ENV（非机密项）
5. **ActiveStorage 本地盘随容器蒸发**：上传文件在容器重建后丢失 → 启动自愈任务（§5.3）
6. **缩略图 URL 输出 `https://localhost`**：`config.default_url_options` 不传导至 routes → `config/initializers/default_url_host.rb` 读 `APP_URL_HOST`（已烧入镜像）

## 1. 架构总览（当前实况）

```
                Cloudflare DNS（randomplayx.com 托管区）
                 │                    │                    │
   randomplayx.com（apex+www）   shop.randomplayx.com   api.randomplayx.com
    CNAME→cname.vercel-dns.com   CNAME→cname.vercel-dns.com  （未绑定）
     灰云（proxied:false）         灰云
          │                              │
   ┌──────▼──────────┐           ┌───────▼────────────┐
   │ SilverForgedGui │  CTA 按钮  │   miao-storefront  │
   │ 3D 引导站(R3F)  │──新标签──▶│  Next.js Spree 店面 │
   │ github独立仓库   │  +UTM     │      (Vercel)      │
   └─────────────────┘           └─────────┬──────────┘
                                           │ REST /api/v3
                                 ┌────────▼────────┐
                                 │ Render 镜像后端  │──▶ Render PG（free）
                                 └─────────────────┘
```

> 2026-08-29 域名布局变更：randomplayx.com 从店铺改为 3D 引导站（体验优先决策，SEO 代价已知悉）；店铺迁至 shop.randomplayx.com。`*.vercel.app` 域名受部署保护有登录墙，两站均以自定义域名对外。

| 组件 | 技术 | 承载 | 部署位置 |
|---|---|---|---|
| 顾客店面 | Next.js（Spree 官方 storefront，源码暂存 §6.2） | 商品浏览、SEO、结账 | Vercel（Hobby 免费档） |
| 商业后台 | Rails 8 + Spree 5.6.1（`backend/`） | Store API `/api/v3`、Admin API | Render（GHCR 镜像，free 档） |
| 数据库 | PostgreSQL 16 | 商品、订单、用户 | Render 托管 Postgres（free） |
| 图片存储 | Active Storage（本地盘） | 9 款产品图烧入镜像 + 启动自愈（§5.3） | 接单前迁 S3/R2 |

## 2. 仓库布局

```
backend/                  # Rails 8 + Spree 5.6.1：Dockerfile、Dockerfile.seed、全部应用代码
backend/db/seeds/
  mock_products.rb        # 9 款苗银 mock 商品（幂等）
  assets/                 # 9 张产品图（1600px JPEG，烧入镜像）
backend/lib/tasks/miao_images.rake   # miao:sync_images 图片自愈
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
# 追加 mock 商品（本地）
cd backend && docker compose run --rm web bin/rails db:seed LOAD_MOCK_PRODUCTS=1
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
  https://api.render.com/v1/services/srv-da993hhsrm7s73bjfrk0/deploys
```

监控：

```bash
render logs --resources srv-da993hhsrm7s73bjfrk0 --limit 50 --output text --confirm   # 应用日志
# 部署状态：GET /v1/services/<SERVICE_ID>/deploys/<DEPLOY_ID>，live 即成功
```

本机 CLI 需先 `render workspace set tea-da38g3lg1s2s73d235eg`。

### 4.3 环境变量管理

线上生效清单（值一律不进仓库）：

| 键 | 值来源 | 说明 |
|---|---|---|
| `DATABASE_URL` | miao-db **内部**连接串 | 经 `GET /v1/postgres/<DB_ID>/connection-info` 取 `internalConnectionString`，PUT env-vars 写入 |
| `RAILS_MASTER_KEY` | `backend/config/master.key` | 泄露即轮换：重新 `rails credentials` 体系 |
| `RAILS_ENV/RAILS_LOG_LEVEL/RAILS_STORAGE_SERVICE/WEB_CONCURRENCY/RAILS_MAX_THREADS` | 固定值 | 见 render.yaml |
| `APP_URL_HOST` | `miao-backend-gecb.onrender.com` | 已烧入 Dockerfile（非机密），修正附件/缩略图绝对 URL |

注意：env-vars 的 PUT 是**全量替换**语义——先 GET 现有列表、变更后整体 PUT 回去。历史教训：API 写入的变量到容器生效可能有延迟甚至失效（见 §0 踩坑 4）。

### 4.4 数据库初始化/重种子（免费档内网执行法）

免费档库不可外部连接，SSH 又被 CLI 锁交互模式——采用**一次性种子服务**：

1. `:seed` 镜像已由流水线自动构建（基于主镜像，CMD 固化为 `bin/rails db:seed LOAD_MOCK_PRODUCTS=1`）
2. 创建一次性 free web 服务（image `:seed` + 内部连接串 + `AUTO_ACCEPT/ADMIN_EMAIL/ADMIN_PASSWORD` 环境变量）
3. 任务跑完进程自然退出 → Render 标记 deploy "update_failed"（**预期现象，非故障**）→ 务必等部署到终态再查日志确认种子输出（`MOCK_PRODUCTS_DONE products=9`）
4. **立即删除该服务**（省免费时长；删除过早会杀死运行中的种子——历史上踩过两次）
5. 种子幂等，重复执行安全
6. 验证：`POST /api/v3/admin/auth/login` 凭管理员账号应返回 200 + JWT；`GET /api/v3/store/products` 应返回 9 款（注意分页 25/页）

重建数据库（到期/换库）：删旧库建新库 → 改服务 `DATABASE_URL` → 触发一次部署（入口脚本自动 db:prepare 全量迁移 + 图片自愈）→ 执行上述种子流程。全程约 10 分钟。

### 4.5 回滚

```bash
# 部署任意历史版本（每次构建都有 :<git-sha> 标签）：
curl -s -X POST ... -d '{"imageUrl": "ghcr.io/bh2-4/miao-backend:<旧sha>"}' \
  https://api.render.com/v1/services/srv-da993hhsrm7s73bjfrk0/deploys
```

注意：代码回滚不回滚数据库 schema；当前库仅结构 + mock 数据，最坏整库重建（§4.4）。

### 4.6 免费档限制与升级路径

| 限制 | 影响 | 升级动作（需在 Render 绑卡） |
|---|---|---|
| 服务 15 分钟无流量休眠 | 冷启动 30-60s（首访慢，店面 SSR 会等后端） | web → starter（$7/月，不休眠） |
| 750 免费时长/月·全工作区 | 仅够一个常驻服务（旧 5 服务已挂起腾位） | 升级后旧服务可按需恢复 |
| Postgres 30 天过期（**9-28**） | 到期整库删除 | db → basic-256mb（$6/月，解锁外部连接 + 每日备份） |
| 无磁盘持久化 | 容器重建丢上传图片 | 已用自愈缓解（§5.3）；接单前迁 S3/Cloudflare R2 |

## 5. Mock 商品数据与图片（当前线上内容）

### 5.1 数据管线

- 定义：`backend/db/seeds/mock_products.rb`（幂等，`find_or_create_by!(slug:)` + `update!`）
- 触发：`bin/rails db:seed LOAD_MOCK_PRODUCTS=1`（rake 参数即环境变量，绕开 Render env 传播不可靠问题；`:seed` 镜像 CMD 已固化此参数）
- 普通种子（店铺/管理员/渠道）仍走 `LOAD_MOCK_PRODUCTS` 未设时的 Spree 引擎种子
- 图片源：`backend/db/seeds/assets/`（9 张 1600px JPEG，源自「苗族银饰3D」实拍，CMYK 已转 sRGB）——**烧入镜像，随部署分发**

线上 9 款（slug → USD）：

| 商品 | slug | 价格 |
|---|---|---|
| 银角头饰（玫瑰流苏） | silver-horn-headdress-rose-tassels | $388 |
| 龙凤银压领 | dragon-phoenix-silver-collar | $420 |
| 月牙多层银项圈 | layered-crescent-silver-collar | $365 |
| 凤尾丝编胸饰 | phoenix-tail-filigree-chest-piece | $460 |
| 太阳纹银胸牌 | sunburst-medallion-chest-ornament | $395 |
| 螺旋银耳环挂件 | spiral-coil-hook-pendant | $340 |
| 青花珐琅银耳钉 | cobalt-lotus-enamel-studs | $58 |
| 霜面炸珠银圈 | frosted-granulated-silver-hoops | $72 |
| 盘丝银手镯 | coiled-rope-silver-bangle | $298 |

### 5.2 商品可见性三道闸（Spree 5.6，排查"商品不见了"必查）

1. `product.status == "active"`：种子内 `product.activate!` 保证
2. `ProductPublication` 存在于该 store 的每个 `Channel`：种子内逐渠道 `find_or_create_by!`
3. Store API 分页 25/页：商品多于 25 时在后续页，别误判为丢失

### 5.3 图片自愈（ActiveStorage 本地盘方案）

- 现象：DB 里 blob 记录在、磁盘文件随容器蒸发 → 404
- 机制：`miao:sync_images`（`backend/lib/tasks/miao_images.rake`）遍历 `Spree::Image`，发现 `blob.service.exist?(key)` 为假且镜像内 `db/seeds/assets/` 有对应文件 → 销毁旧记录重挂载
- 触发：`bin/docker-entrypoint` 在 `db:prepare` 后、每次服务启动时执行
- 前提：镜像含 assets（§5.1）；换图需更新 assets 并重新构建部署

## 6. 店面（Vercel，已上线）

### 6.1 当前部署

- 源码：Spree 官方 Next.js storefront（Next.js 16 + pnpm），上游锁定 commit `e1b2cc76335fe9a419afb090db5ef5da61432bab`
- Vercel 项目：`miao-storefront`（Hobby 免费档），生产部署 READY
- 环境变量（Vercel 侧）：`SPREE_API_URL=https://miao-backend-gecb.onrender.com`、`SPREE_PUBLISHABLE_KEY=pk_by3q8DrnxB1uzw48DUnWrgeP`
- 域名：apex + www 已分配且 verified；www 301 → apex；部署保护 `all_except_custom_domains`（自定义域名公开，`*.vercel.app` 需登录属预期）
- 更新方式（当前无 Git 集成）：在店面源码目录 `pnpm i && vercel deploy --prod`（需 VERCEL_TOKEN）

### 6.2 ⚠️ 源码位置（待办：入库）

店面源码**尚未进入本仓库**：
- 暂存：`/tmp/storefront-stage/`（易失，重启即没）
- 备份：`~/miao-backups/storefront-2026-08-29.tar.gz`（1MB，排除 node_modules，含 .env.local）
- 未入库原因：安全扫描对上游测试夹具（硬编码假凭据 ×4）与 `send.ts` 文件名处理（实为白名单正则、安全）误报 HIGH，阻断提交
- 入库方案（下一步）：加固 `send.ts` 说明注释 + 移除/改写触发误报的测试夹具文件，或以 `--no-verify` 例外流程提交并附扫描备注

### 6.3 上游已知 issue 对照表（2026-08-29 审计）

快照 `e1b2cc7` 即上游 main 最新提交（2026-07-29 后无新提交），无需追版本。已知开放 bug 与我们的关系：

| Issue | 症状 | 对本站影响 |
|---|---|---|
| spree/storefront#208 | 国家/语言切换异常：us/en → jp/ja 被弹回，us/en → gb/en-GB 报错 | ⚠️ 顾客可感知；规避：暂只用默认 us/en，等上游修复后同步快照 |
| spree/spree#14334 | 商品挂**顶级**分类后在 dashboard/店面都打不开 | ✅ 不受影响（种子挂二级分类）；⚠️ 将来在 admin 手动建商品时勿直接挂根分类 `Categories` |
| spree/spree#14365 | Admin 后台移动端菜单空白 | 仅影响手机管理后台，桌面不受影响 |
| spree/spree#14113 | Next.js 店面结算：物流规则/国家限制对登录用户不校验 | 未接支付前无影响；**开站配置物流规则前必须复查**（加入 §8 清单） |

另：Store API v3 单资源响应为**扁平 JSON**（无 `data` 包裹层），列表响应才有 `data` 数组——写对接脚本时注意。

### 6.4 本地跑店面

```bash
cd /tmp/storefront-stage
pnpm install
pnpm dev    # :3001，.env.local 已指向线上后端
```

## 7. 域名与 DNS（Cloudflare）

当前布局（2026-08-29 域名互换后）：
1. apex：`CNAME randomplayx.com → cname.vercel-dns.com`，灰云 → **SilverForgedGui 3D 引导站**
2. www：`CNAME www → cname.vercel-dns.com`，灰云 → 同上演示站（Vercel 侧 301 → apex）
3. shop：`CNAME shop → cname.vercel-dns.com`，灰云 → **本仓库 Next.js 店面（miao-storefront）**
4. 旧站（blackrelaxing-index.pages.dev）已下线；同 zone 其他记录（pilot/resume/shumo/mvp）未动
5. 互换执行顺序（防冲突，已验证）：目标项目先加新城名 → 原项目**先移除带 301 的 www**（409 陷阱：apex 被 www 引用时删不掉）→ 再移除 apex → 新项目接管 apex → www 重挂并配 301

待做：
- **api.randomplayx.com** → `CNAME api → miao-backend-gecb.onrender.com`（灰云），再在 Render Dashboard → miao-backend → Settings → Custom Domains 添加该域名完成签发；随后把店面 `SPREE_API_URL` 切到 `https://api.randomplayx.com` 并重新部署店面
- SSL/TLS 模式建议 **Full (strict)** + Always Use HTTPS（现全部灰云，模式暂不影响）

回滚（店铺收回主域名）：silverforgedgui 移除 apex/www → miao-storefront 重新加 randomplayx.com（+ www 301）→ shop 记录可留作备用。全程仅 Vercel API 操作，DNS 不动，约 10 分钟。

DNS 变更操作（API，token 在 `~/.cf-key`）：
```bash
CF_TOKEN=$(cat ~/.cf-key)
curl -s -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/41a6e698ef8bec7aaba7d0253b76dd73/dns_records"
```

## 8. 正式开站前清单（外贸合规与转化）

- [ ] 支付：Stripe / PayPal 开通（用户已确认暂缓），`randomplayx.com` 审核前政策页齐全可访问
- [ ] 支付前复查 spree/spree#14113：登录用户结算不校验物流规则/国家限制（见 §6.3）
- [ ] 政策页（店面承载）：Privacy / Terms / Return & Refund / Shipping
- [ ] 合规：对美 ≤$800/单 de minimis；原产国标识；银饰纯度如实标注（S925/S999）
- [ ] 宣传红线：不使用「保值/投资/治病」类表述
- [ ] GA4 + Search Console（apex 与 www 都验证）+ sitemap
- [ ] 品牌化：店面标题/描述仍是 "Spree Store" 默认值，需换 Miao 品牌；og:url/canonical 仍指向 `miao-storefront-beta.vercel.app`（上游默认 metadata），需改为 shop.randomplayx.com
- [ ] 域名邮箱 + WhatsApp Business
- [ ] 产品图迁 S3/R2；Render PG 升级并开启每日备份
- [ ] 管理后台强密码 + 后台限 IP（Cloudflare Access/WAF）

## 9. 安全事项

- [ ] **轮换 Render API key**（曾出现在聊天记录）：Dashboard → Settings → API Keys
- [ ] **轮换 Vercel token**（曾出现在聊天记录）
- [ ] **轮换 Cloudflare token**（曾出现在聊天记录）
- [ ] **更换生产 admin 密码**（当前为开发级密码）
- [ ] GHCR 包转私有 + Render 配 registryCredential（镜像含生产代码）
- [ ] `master.key`、`.env*`、连接串永不入库；GitHub secrets 现有：`RENDER_DB_URL`（外部串，free 档下已无用，可删）、`RAILS_MASTER_KEY`、`ADMIN_PASSWORD`
- [ ] free 档库到期即删——不要往里面放任何舍不得的数据（9-28 前§4.4 重建或升级）

## 10. 成本概览

| 阶段 | 配置 | 月成本 |
|---|---|---|
| 试跑（当前） | Render free ×2（web+db）+ Vercel Hobby + Cloudflare Free | $0 |
| 正式接单 | Render starter + basic-256mb + Vercel Pro（商用条款） | ~$33 |
