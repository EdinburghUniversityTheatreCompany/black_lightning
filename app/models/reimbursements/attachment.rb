module Reimbursements
  ##
  # A file attached to an Airtable record. Airtable's URLs are signed and
  # expire after ~2 hours — never persist or cache them beyond the record fetch.
  class Attachment
    attr_reader :attachment_id, :filename, :url, :size_bytes, :content_type, :thumbnail_url

    def initialize(attachment_id:, filename:, url:, size_bytes: 0, content_type: "", thumbnail_url: nil)
      @attachment_id = attachment_id
      @filename = filename
      @url = url
      @size_bytes = size_bytes
      @content_type = content_type
      @thumbnail_url = thumbnail_url
    end

    def image?
      content_type.to_s.start_with?("image/")
    end

    # Airtable generates thumbnails asynchronously, so a just-uploaded image
    # has none yet; previewing the full file bridges the gap.
    def preview_url
      thumbnail_url.presence || (url if image?)
    end
  end
end
