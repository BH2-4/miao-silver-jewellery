# Miao Silver Jewellery — 贵州苗银外贸独立站

面向海外市场的贵州苗族银饰（Miao Silver）品牌独立站代码与部署仓库。

- 正式域名：`randomplayx.com`（已托管于 Cloudflare；当前承载旧站点，正式切换前需确认旧内容下线）
- 托管平台：Cloudflare Pages（完整流程见 `docs/DEPLOYMENT.md`）
- 当前状态：占位站点（`public/index.html`，已加 `noindex`），正式店铺代码后续迁入

## 仓库结构

```
public/               # 站点静态资源（当前为占位首页）
docs/DEPLOYMENT.md    # 正式部署流程：域名绑定、发布、回滚、开站清单
```

## 本地预览

```bash
python3 -m http.server 8080 --directory public
# 访问 http://localhost:8080
```

## 发布

`git push` 到 `main` 后由 Cloudflare Pages 自动构建部署，无需手动操作。域名绑定、回滚与开站前合规清单见 `docs/DEPLOYMENT.md`。
