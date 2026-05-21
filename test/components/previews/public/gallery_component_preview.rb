class Public::GalleryComponentPreview < ViewComponent::Preview
  def default
    render Public::GalleryComponent.new(pictures: Picture.accessible_by(Ability.new(User.first)).limit(8))
  end

  def with_custom_header_size
    render Public::GalleryComponent.new(pictures: Picture.accessible_by(Ability.new(User.first)).limit(4), header_size: 4)
  end

  def empty
    render Public::GalleryComponent.new(pictures: Picture.none)
  end
end
