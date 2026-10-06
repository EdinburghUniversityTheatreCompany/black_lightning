class GalleryComponentPreview < ViewComponent::Preview
  def default
    render GalleryComponent.new(pictures: pictures(8))
  end

  def with_custom_header_size
    render GalleryComponent.new(pictures: pictures(4), header_size: 4)
  end

  # What the admin screens render: each caption gains the picture's tags.
  def with_tags
    render GalleryComponent.new(pictures: pictures(4), show_tags: true)
  end

  def empty
    render GalleryComponent.new(pictures: Picture.none)
  end

  private

  def pictures(limit) = Picture.accessible_by(Ability.new(User.first)).limit(limit)
end
