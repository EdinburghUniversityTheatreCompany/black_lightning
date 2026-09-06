class GalleryComponent < ViewComponent::Base
  # show_tags adds each picture's tags under its caption, linked to the admin
  # tag pages. Admin callers pass it; the public show pages leave it off, which
  # is what the old partial's `@admin_site &&` gate did from inside the markup.
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
