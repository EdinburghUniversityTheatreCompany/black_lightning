module Reimbursements
  ##
  # A file attached to an Airtable record. Airtable's URLs are signed and
  # expire after ~2 hours — never persist or cache them beyond the record fetch.
  class Attachment
    attr_reader :attachment_id, :filename, :url, :size_bytes, :content_type

    def initialize(attachment_id:, filename:, url:, size_bytes: 0, content_type: "")
      @attachment_id = attachment_id
      @filename = filename
      @url = url
      @size_bytes = size_bytes
      @content_type = content_type
    end
  end
end
