class GalleryComponent < ViewComponent::Base
  # show_tags lists each picture's tags under its caption: admin callers pass it
  # (the old `@admin_site` gate), public pages leave it off.
  def initialize(pictures:, header_size: 3, show_tags: false)
    @pictures = pictures
    @header_size = header_size
    @show_tags = show_tags
  end

  private

  def any_pictures?
    @pictures.any?
  end

  def header_tag
    "h#{@header_size}"
  end

  def tags_for(picture)
    return [] unless @show_tags

    picture.picture_tags
  end
end
