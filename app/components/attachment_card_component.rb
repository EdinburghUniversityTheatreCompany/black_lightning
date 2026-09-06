class AttachmentCardComponent < ViewComponent::Base
  # Fallback icons for the attachments ActiveStorage cannot make a thumbnail of.
  # Keyed by content type, so a type added to Attachment::ALLOWED_CONTENT_TYPES
  # gets the generic file icon until it is named here.
  CONTENT_TYPE_ICONS = {
    "application/pdf" => "fa-file-pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "fa-file-word",
    "application/msword" => "fa-file-word",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "fa-file-excel",
    "application/vnd.ms-excel" => "fa-file-excel",
    "text/plain" => "fa-file-lines",
    "application/x-musescore" => "fa-file-audio",
    "application/x-musescore+xml" => "fa-file-audio",
    "application/vnd.recordare.musicxml+xml" => "fa-file-audio",
    "application/vnd.recordare.musicxml" => "fa-file-audio",
    "audio/midi" => "fa-file-audio",
    "application/x-sibelius" => "fa-file-audio",
    "text/x-lilypond" => "fa-file-audio",
    "text/vnd.abc" => "fa-file-audio"
  }.freeze

  DEFAULT_ICON = "fa-file".freeze

  def initialize(attachment:, include_item_link: false)
    @attachment = attachment
    @include_item_link = include_item_link
  end

  private

  def path
    helpers.attachment_path(@attachment.slug)
  end

  def fullsize_url
    helpers.url_for(@attachment.file)
  end

  # nil when ActiveStorage cannot render a preview at all, which is the signal
  # to fall back to an icon.
  def thumbnail
    file = @attachment.file
    file.previewable? ? file.preview(helpers.thumb_variant) : file.variant(helpers.thumb_variant)
  rescue ActiveStorage::InvariableError, ActiveStorage::Unpreviewable
    nil
  end

  def icon_class
    CONTENT_TYPE_ICONS.fetch(@attachment.file.content_type, DEFAULT_ICON)
  end

  def item_url
    helpers.get_url_for_attachment_item(@attachment)
  end

  def show_item_link?
    @include_item_link && @attachment.item.present?
  end
end
