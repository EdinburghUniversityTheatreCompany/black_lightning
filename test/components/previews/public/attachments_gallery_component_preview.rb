class Public::AttachmentsGalleryComponentPreview < ViewComponent::Preview
  def default
    render Public::AttachmentsGalleryComponent.new(
      attachments: Attachment.accessible_by(Ability.new(User.first)).limit(8)
    )
  end

  def without_header
    render Public::AttachmentsGalleryComponent.new(
      attachments: Attachment.accessible_by(Ability.new(User.first)).limit(4),
      include_header: false
    )
  end

  def with_item_links
    render Public::AttachmentsGalleryComponent.new(
      attachments: Attachment.accessible_by(Ability.new(User.first)).limit(4),
      include_item_link: true
    )
  end

  def empty
    render Public::AttachmentsGalleryComponent.new(attachments: Attachment.none)
  end
end
