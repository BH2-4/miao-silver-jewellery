# Storefront（Next.js）

上游：spree/storefront@e1b2cc76335fe9a419afb090db5ef5da61432bab（main，2026-08-29 vendor）

## 本地化说明

- 官方 Next.js 16 店面（pnpm），对接 Spree Store API `/api/v3`
- 接入后端：`storefront/.env.local`
  - `SPREE_API_URL`：生产 `https://miao-backend-gecb.onrender.com`；本地联调 `http://localhost:3000`
  - `SPREE_PUBLISHABLE_KEY`：后端 Admin API `/api/v3/admin/api_keys` 取 publishable 类型
- `.env.local` 已被上游 .gitignore 覆盖，勿提交
- 本地预览：`pnpm install && pnpm dev`（端口 3001；国内网络 `pnpm config set registry https://registry.npmmirror.com`）
- 部署：Vercel Import 本仓库，Root Directory 选 `storefront/`
- 上游同步：以本文件记录的 SHA 为基线做 diff/patch
