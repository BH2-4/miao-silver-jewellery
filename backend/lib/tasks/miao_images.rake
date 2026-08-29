# frozen_string_literal: true

# 自愈：本地磁盘存储下，容器重建会丢失 ActiveStorage 文件（DB 记录仍在）。
# 对 db/seeds/assets 内置的 mock 商品图，检测到文件缺失时从镜像内原件重新挂载。
# 由 bin/docker-entrypoint 在服务启动前调用；未来迁移 S3/R2 后此任务自动变 no-op。
namespace :miao do
  desc "Re-attach seed images whose backing files are missing"
  task sync_images: :environment do
    fixed = 0
    Spree::Image.includes(attachment_attachment: :blob).find_each do |image|
      attachment = image.attachment
      blob = attachment&.blob
      next if blob.nil? || blob.service.exist?(blob.key)

      viewable = image.viewable
      filename = blob.filename.to_s
      path = Rails.root.join("db/seeds/assets", filename)

      unless File.exist?(path)
        puts "MIAO: missing file and no baked asset for #{filename}, skipping"
        next
      end

      image.destroy!
      Spree::Image.create!(
        viewable: viewable,
        attachment: { io: File.open(path), filename: filename, content_type: blob.content_type || "image/jpeg" }
      )
      fixed += 1
      puts "MIAO: re-attached #{filename}"
    end
    puts "MIAO: sync_images done, fixed=#{fixed}"
  end
end
