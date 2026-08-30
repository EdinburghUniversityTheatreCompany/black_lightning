xml.instruct! :xml, version: "1.0", encoding: "UTF-8"

xml.sitemapindex(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
  @sections.each do |section|
    xml.sitemap do
      xml.loc section_sitemap_url(section)
    end
  end
end
