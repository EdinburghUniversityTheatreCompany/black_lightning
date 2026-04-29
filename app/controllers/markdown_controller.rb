##
# Controller to render a markdown preview.
#
# Use POST /markdown/preview with the post body set to the content
# to be rendered.
##

class MarkdownController < ApplicationController
  include MdHelper

  skip_authorization_check

  ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  def preview
    body = ActiveSupport::JSON.decode(request.body.read)
    input_html = CGI.unescape(body["input_html"])

    response = { rendered_md: render_markdown(input_html) }

    render json: response
  end

  def upload
    file = params[:image]

    unless file.is_a?(ActionDispatch::Http::UploadedFile) &&
           ALLOWED_IMAGE_TYPES.include?(file.content_type)
      render json: { error: "Invalid file type" }, status: :unprocessable_entity
      return
    end

    item = resolve_item(params[:item_type], params[:item_id])

    stem = File.basename(file.original_filename, ".*").parameterize.truncate(40, omission: "")
    attachment = Attachment.new(
      name: "md-upload-#{stem}-#{SecureRandom.hex(4)}",
      access_level: 2,
      item: item
    )
    attachment.file.attach(
      io: file.open,
      filename: file.original_filename,
      content_type: file.content_type
    )

    if attachment.save
      render json: { url: attachment_path(attachment.slug), alt: attachment.name }
    else
      render json: { error: attachment.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def resolve_item(item_type, item_id)
    return nil if item_type.blank? || item_id.blank?

    klass = item_type.safe_constantize
    return nil unless klass && klass < ApplicationRecord

    klass.find_by(id: item_id)
  end
end
