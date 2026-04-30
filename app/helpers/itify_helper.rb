module ItifyHelper
  def itify_head_urls
    Dir[Rails.root.join("app/assets/images/easter_egg/*.{png,jpg,jpeg,gif,webp}")]
      .reject { |f| File.basename(f).include?("pineapple") }
      .map { |f| asset_path("easter_egg/#{File.basename(f)}") }
  end
end
