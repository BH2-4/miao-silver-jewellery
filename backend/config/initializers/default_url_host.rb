# 图片等绝对 URL 的对外主机名。
# Store API 序列化器经 Rails.application.routes.url_helpers 生成 cdn_image_url，
# 其 default_url_options 必须在路由加载后显式赋值（environment 的
# config.default_url_options 不会传导到主应用路由表）。
if (host = ENV["APP_URL_HOST"].presence)
  Rails.application.routes.default_url_options = { host: host, protocol: "https" }
end
