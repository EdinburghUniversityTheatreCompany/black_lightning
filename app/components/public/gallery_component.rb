class Public::GalleryComponent < ViewComponent::Base
  def initialize(pictures:, header_size: 3)
    @pictures = pictures
    @header_size = header_size
  end

  private

  def any_pictures?
    @pictures.any?
  end

  def header_tag
    "h#{@header_size}"
  end
end
