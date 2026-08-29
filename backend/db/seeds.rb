# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# 判决器：无论走哪条分支都打印 gate 实际值（区分 env 传播失败 vs 脚本问题）
puts "SEED_GATES load_mock=#{ENV['LOAD_MOCK_PRODUCTS'].inspect} (rake 参数亦可设置: bin/rails db:seed LOAD_MOCK_PRODUCTS=1)"

# Spree 引擎种子不可重入：LOAD_MOCK_PRODUCTS=1 时跳过（仅追加 mock 商品）
Spree::Core::Engine.load_seed if defined?(Spree::Core) && ENV["LOAD_MOCK_PRODUCTS"] != "1"

# 苗银 mock 商品（试跑数据）：LOAD_MOCK_PRODUCTS=1 时加载
load Rails.root.join("db/seeds/mock_products.rb") if ENV["LOAD_MOCK_PRODUCTS"] == "1"
