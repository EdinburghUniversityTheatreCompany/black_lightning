module Reimbursements
  ##
  # View-friendly wrapper over a receipt's ActiveStorage blob. Every URL is
  # host-relative and permission-checked (ReceiptFilesController), so anything
  # needing the content (the SharePoint offload) must call +bytes+: a remote
  # fetcher has no session.
  class Attachment
    attr_reader :attachment_id, :filename, :url, :content_type, :thumbnail_url

    def initialize(attachment_id:, filename:, url:, content_type: "",
                   thumbnail_url: nil, download_url: nil, blob: nil)
      @attachment_id = attachment_id
      @filename = filename
      @url = url
      @content_type = content_type
      @thumbnail_url = thumbnail_url
      @download_url = download_url
      @blob = blob
    end

    def bytes
      @blob&.download
    end

    def image?
      content_type.to_s.start_with?("image/")
    end

    def pdf?
      content_type.to_s == "application/pdf"
    end

    # Falls back to the full image when there is no thumbnail.
    def preview_url
      thumbnail_url.presence || (url if image?)
    end

    # Expense.wrap_receipt sets thumbnail_url for anything representable?, PDFs
    # (first page) included, so ask about the capability, not the content type.
    def previewable?
      preview_url.present?
    end

    # Images directly, PDFs through the native viewer. Anything else, which only a
    # receipt predating ReceiptIntake can be, has to be downloaded.
    def inline_viewable?
      image? || pdf?
    end

    # Always saves rather than displays; the HTML download attribute is ignored
    # cross-origin.
    def download_url
      @download_url.presence || url
    end
  end
end
