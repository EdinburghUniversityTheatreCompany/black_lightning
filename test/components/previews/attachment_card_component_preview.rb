class AttachmentCardComponentPreview < ViewComponent::Preview
  def default
    render AttachmentCardComponent.new(attachment: Attachment.first)
  end

  # The attachments index shows what each file is attached to.
  def with_item_link
    render AttachmentCardComponent.new(attachment: Attachment.first, include_item_link: true)
  end

  # A type ActiveStorage cannot thumbnail falls back to an icon.
  def without_a_thumbnail
    render AttachmentCardComponent.new(attachment: unpreviewable_attachment || Attachment.first)
  end

  private

  def unpreviewable_attachment
    Attachment.joins(file_attachment: :blob)
              .where.not(active_storage_blobs: { content_type: %w[image/png image/jpeg image/webp image/gif application/pdf] })
              .first
  end
end
