module MetaHelper
  def meta_tags
    @meta[:title] ||= @title ? "#{@title} - Bedlam Theatre" : "Bedlam Theatre"
    @meta[:description] ||= "The Bedlam Theatre is a unique, entirely student run theatre in the heart of Edinburgh."

    # facebook opengraph data:
    @meta["og:url"]         ||= @base_url + request.fullpath
    @meta["og:image"]       ||= @base_url + image_path('BedlamLogoBW.png')
    @meta["og:title"]       ||= @meta[:title]
    @meta["og:description"] ||= @meta[:description]

    @tags = []

    @meta.each do |name, content|
      type = "name"
      type = "property" if name.to_s.starts_with?('og') or name.to_s.starts_with?('fb')

      if content.kind_of?(Array) then
        content.each do |item|
          @tags << "<meta #{type}='#{name}' content='#{ERB::Util.html_escape item}'>"
        end
      else
        @tags << "<meta #{type}='#{name}' content='#{ERB::Util.html_escape content}'>"
      end
    end

    return @tags.join "\n"
  end
end