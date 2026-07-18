module Reimbursements
  ##
  # A file attached to an expense. On the Airtable backend +url+ is a signed
  # URL that expires after ~2 hours — never persist or cache it beyond the
  # record fetch. On the database backend the wrapper carries the
  # ActiveStorage +blob+, so consumers that need the content (AiChecker,
  # BatchProcessor's SharePoint offload) call +bytes+ and fall back to
  # downloading +url+ only in the Airtable era.
  class Attachment
    attr_reader :attachment_id, :filename, :url, :size_bytes, :content_type, :thumbnail_url

    def initialize(attachment_id:, filename:, url:, size_bytes: 0, content_type: "",
                   thumbnail_url: nil, blob: nil)
      @attachment_id = attachment_id
      @filename = filename
      @url = url
      @size_bytes = size_bytes
      @content_type = content_type
      @thumbnail_url = thumbnail_url
      @blob = blob
    end

    # The file content when locally stored (database backend), nil otherwise.
    def bytes
      @blob&.download
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
