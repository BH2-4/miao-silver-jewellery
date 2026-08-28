# 正式部署流程 · randomplayx.com

> 仓库：`miao-silver-jewellery` ｜ 用途：贵州苗银外贸独立站 ｜ 最后更新：2026-08-28

## 0. 现状与前提

已核实现状（2026-08-28）：

- ✅ 域名 `randomplayx.com` 已注册，DNS 托管在 Cloudflare（NS：felicity / mckinley.ns.cloudflare.com）
- ⚠️ 该域名当前已承载旧站点「Random Play X — 链接索引」。**正式绑定新站 = 替换旧站内容**，切换前需与旧站负责人确认；过渡期可先用 `*.pages.dev` 预览地址完成验收
- ✅ GitHub 仓库已就绪，`main` 为生产分支

技术选型：

| 项 | 选择 | 说明 |
|---|---|---|
| 代码托管 | GitHub | push 到 `main` 自动触发部署 |
| 托管 | Cloudflare Pages | 全球 CDN、自动 SSL、免费额度；Vercel 为等效备选 |
| 域名 | randomplayx.com | 海外注册 + 海外托管，无需 ICP 备案；不得面向中国大陆提供经营性服务 |
| 站点 | 静态占位页 → 正式电商站（Next.js / Astro） | 占位阶段 Output 目录为 `public/` |

前置条件：

- [ ] 可登录域名所在的 Cloudflare 账号
- [ ] Cloudflare 已授权连接 GitHub（Workers & Pages 首次连接时授权）
- [ ] （建议）为品牌注册域名邮箱（Google Workspace / Zoho Mail）

## 1. 首次部署（Cloudflare Pages）

1. Cloudflare Dashboard → **Workers & Pages → Create → Pages → Connect to Git**
2. 授权 GitHub，选择仓库 `miao-silver-jewellery`
3. 构建配置（占位阶段）：
   - Framework preset：`None`
   - Build command：留空
   - Build output directory：`public`
4. **Save and Deploy** → 得到 `https://<项目名>.pages.dev` 预览地址

> 迁移到 Next.js / Astro 后仅改两条构建配置：Build command 改为 `npm run build`（按实际），Output 改为对应产物目录（如 `.next` / `dist`），其余流程不变。

### Vercel 备选流程

Import Git Repository → 选择本仓库 → Framework preset 选 `Other`，Output Directory 填 `public` → Deploy。域名绑定方式同理。

## 2. 绑定正式域名 randomplayx.com

1. Pages 项目 → **Custom domains → Set up a custom domain** → 输入 `randomplayx.com`
2. 再添加 `www.randomplayx.com` 作为别名
3. DNS 记录（域名与 Pages 同在 Cloudflare 账号时，面板会**自动添加**；跨账号或外部 DNS 时手动添加）：

| 类型 | 主机记录 | 记录值 | 代理 |
|---|---|---|---|
| CNAME | `@` | `<项目名>.pages.dev` | 开启（橙云） |
| CNAME | `www` | `<项目名>.pages.dev` | 开启（橙云） |

4. SSL：证书由 Cloudflare 自动签发与续期；SSL/TLS 加密模式设为 **Full (strict)**，开启 **Always Use HTTPS**
5. 主域归一化：将 `www` 设置为 redirect 到 `randomplayx.com`（保留一种 canonical 形式，利于 SEO）

## 3. 上线验收标准

- [ ] `https://randomplayx.com` 返回 200，证书链有效（SSL Labs 评级 ≥ A）
- [ ] `http://` 与 `www.` 均 301 到 `https://randomplayx.com`
- [ ] Lighthouse（移动端）：Performance ≥ 90、SEO ≥ 90
- [ ] 移动端（375px / 414px）无布局错乱
- [ ] 回滚演练：执行一次 Rollback 并恢复到最新版本

## 4. 日常发布流程

```
功能分支 → Pull Request（自动生成预览 URL）→ Review 通过 → merge 到 main
        → Cloudflare Pages 自动构建部署（约 1–2 分钟）→ 生产环境更新
```

- 生产问题回滚：**Deployments → 上一个成功部署 → Rollback to this deployment**，秒级生效
- 建议在 GitHub 开启 `main` 分支保护（要求 PR 通过后合并）

## 5. 正式开站前清单（外贸合规与转化）

- [ ] **支付通道**：Stripe / PayPal 开户，并提交 `randomplayx.com` 网站审核（要求政策页齐全、可正常访问）
- [ ] **政策页**：Privacy Policy、Terms of Service、Return & Refund Policy、Shipping Policy（支付通道审核硬性要求）
- [ ] **分析与收录**：GA4 接入、Google Search Console 验证主域并提交 sitemap
- [ ] **SEO 基线**：品牌 Title / Description、产品页 Product 结构化数据、Open Graph；**移除占位页中的 `noindex`**
- [ ] **联系方式**：域名邮箱、WhatsApp 商务号、页脚公司信息
- [ ] **性能**：产品图 WebP + 懒加载、确认 CDN 缓存命中
- [ ] **宣传合规**：银饰纯度如实标注（S925 / S999 等），避免「保值」「投资」类宣传语

## 6. 环境变量与密钥管理

- 全部在平台侧配置：Pages → Settings → **Environment variables**，Production 与 Preview 分开配置
- `.env*` 已被 `.gitignore` 覆盖，禁止提交任何密钥进仓库
- 密钥泄露应急：平台侧立即轮换 → 用 `git filter-repo` 清理历史并 force push → 必要时联系 GitHub Support 清理缓存

## 7. 应急与回滚

| 场景 | 动作 |
|---|---|
| 新版本有 bug | Deployments → Rollback 到上一个成功版本，秒级生效 |
| 域名解析故障 | 检查 DNS 记录；临时将流量切回 `*.pages.dev` 或挂维护页 |
| 平台故障 | Vercel 接入同一仓库作为热备，DNS 切换即可恢复 |
