class Public::AttachmentsGalleryComponent < ViewComponent::Base
  def initialize(attachments:, include_item_link: false, include_header: true)
    @attachments = attachments
    @include_item_link = include_item_link
    @include_header = include_header
  end

  private

  def any_attachments?
    @attachments.any?
  end
end
