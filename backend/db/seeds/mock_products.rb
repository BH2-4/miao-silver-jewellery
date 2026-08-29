# frozen_string_literal: true

# 苗银 mock 商品种子：由 db/seeds.rb 在 LOAD_MOCK_PRODUCTS=1 时加载。
# 幂等：按 slug find_or_create；文案/价格/库存每次刷新；图片仅在缺失时挂载。
# 图片资产：db/seeds/assets/（苗族银饰3D 文件夹精选，试跑期数据）。

store = Spree::Store.order(:id).first
abort "MOCK: no store found, run base seeds first" unless store

shipping_category = Spree::ShippingCategory.find_or_create_by!(name: "Default")
stock_location = Spree::StockLocation.find_or_create_by!(name: "Default")
taxonomy = store.taxonomies.find_or_create_by!(name: "Categories")
root_taxon = taxonomy.root

ensure_taxon = lambda do |name|
  root_taxon.children.find_or_create_by!(name: name)
end

assets_dir = Rails.root.join("db/seeds/assets")

# rubocop:disable Layout/LineLength
PRODUCTS = [
  {
    name: "Silver Horn Headdress with Rose & Tassels",
    slug: "silver-horn-headdress-rose-tassels",
    price: 388.00,
    taxon: "Headdress",
    image: "silver-horn-headdress.jpg",
    description: "A statement festival headdress crowned with a fan of radiating silver blades and crescent horn elements, finished with a pink silk rose and swaying tassel fringe. The engraved headband and fine filigree showcase the full range of traditional Miao silversmithing from the Guizhou highlands."
  },
  {
    name: "Dragon-Phoenix Silver Collar · Twelve Spirals",
    slug: "dragon-phoenix-silver-collar",
    price: 420.00,
    taxon: "Necklaces",
    image: "dragon-phoenix-collar.jpg",
    description: "A broad crescent torc engraved with intertwined dragon and phoenix motifs around an auspicious central medallion, suspended with twelve coiled spiral discs that catch the light with every movement. Hand-raised, chased and polished by Miao artisans."
  },
  {
    name: "Layered Crescent Silver Collar",
    slug: "layered-crescent-silver-collar",
    price: 365.00,
    taxon: "Necklaces",
    image: "layered-crescent-collar.jpg",
    description: "Layered crescent bands engraved with dragon and floral scroll, joined by hand-coiled ring connectors and edged with spiral-cone pendants. A wearable architecture of texture that drapes beautifully on the collarbone."
  },
  {
    name: "Phoenix Tail Filigree Chest Piece",
    slug: "phoenix-tail-filigree-chest-piece",
    price: 460.00,
    taxon: "Chest Pieces",
    image: "phoenix-filigree-chest-piece.jpg",
    description: "A majestic phoenix spreads its tail in layered, fan-like feathers — each formed from fine twisted silver wire, coiled spirals and tiny granulation beads. The pinnacle of Miao filigree (花丝) technique, museum-grade craftsmanship."
  },
  {
    name: "Sunburst Medallion Chest Ornament",
    slug: "sunburst-medallion-chest-ornament",
    price: 395.00,
    taxon: "Chest Pieces",
    image: "sunburst-medallion-chest-ornament.jpg",
    description: "Symmetrical rows of sunburst medallions, floral plaques and butterfly motifs cascade into tassels and tiny silver bells that chime as you move. A full ceremonial front piece combining filigree, repoussé and chain-link work."
  },
  {
    name: "Spiral Coil Hook Pendant",
    slug: "spiral-coil-hook-pendant",
    price: 340.00,
    taxon: "Chest Pieces",
    image: "spiral-coil-hook-pendant.jpg",
    description: "A bold curved hook pendant flanked by snail-shell spiral discs, each hand-wound from concentric rings of silver wire. The iconic Miao spiral motif — a symbol of prosperity and protection — in its purest form."
  },
  {
    name: "Cobalt Lotus Enamel Studs",
    slug: "cobalt-lotus-enamel-studs",
    price: 58.00,
    taxon: "Earrings",
    image: "cobalt-lotus-enamel-studs.jpg",
    description: "Lotus blossoms in deep cobalt-blue enamel set in high-silver alloy, each finished with a small dangling bead for gentle movement. Lightweight everyday elegance from a centuries-old enamel tradition."
  },
  {
    name: "Frosted Granulated Silver Hoops",
    slug: "frosted-granulated-silver-hoops",
    price: 72.00,
    taxon: "Earrings",
    image: "frosted-granulated-hoops.jpg",
    description: "Hand-hammered and stippled hoops with a frost-like granulated surface that scatters light like fresh snow. Minimalist in form, entirely traditional in technique."
  },
  {
    name: "Coiled Rope Silver Bangle · Museum Heritage",
    slug: "coiled-rope-silver-bangle",
    price: 298.00,
    taxon: "Bracelets",
    image: "coiled-rope-bangle.jpg",
    description: "An open-form bangle with a substantial coiled rope-textured band, rendered in repoussé relief of repeated linked motifs and carrying a soft aged patina. A heritage design documented from museum collections of the Yunnan–Guizhou region."
  }
].freeze
# rubocop:enable Layout/LineLength

PRODUCTS.each do |item|
  taxon = ensure_taxon.call(item[:taxon])

  product = Spree::Product.find_or_create_by!(slug: item[:slug]) do |p|
    p.name = item[:name]
    p.price = item[:price]
    p.description = item[:description]
    p.shipping_category = shipping_category
  end
  product.update!(
    name: item[:name],
    description: item[:description],
    price: item[:price],
    available_on: product.available_on || 1.day.ago
  )

  # Store API 只展示 active 商品；新建默认 draft
  begin
    product.activate! unless product.status == "active"
  rescue StandardError => e
    puts "MOCK: activate failed for #{item[:slug]}: #{e.message}"
  end

  product.taxons << taxon unless product.taxons.include?(taxon)

  begin
    stock_item = stock_location.stock_items.find_or_create_by!(variant: product.master)
    stock_item.update!(count_on_hand: 100, backorderable: true)
  rescue StandardError => e
    puts "MOCK: stock skipped for #{item[:slug]}: #{e.message}"
  end

  if product.images.empty?
    path = assets_dir.join(item[:image])
    Spree::Image.create!(
      viewable: product.master,
      attachment: {
        io: File.open(path),
        filename: item[:image],
        content_type: "image/jpeg"
      }
    )
    puts "MOCK: image attached #{item[:image]}"
  end

  puts "MOCK: product ready #{item[:slug]} ($#{item[:price]})"
end

puts "MOCK_PRODUCTS_DONE products=#{Spree::Product.count}"

begin
  pk = Spree::ApiKey.where(key_type: "publishable", revoked_at: nil).order(:id).first
  puts "PUBLISHABLE_KEY=#{pk.token}" if pk
rescue StandardError => e
  puts "MOCK: publishable key lookup failed: #{e.message}"
end
