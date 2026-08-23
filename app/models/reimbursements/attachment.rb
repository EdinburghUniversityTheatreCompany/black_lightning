module Reimbursements
  ##
  # A file attached to an expense: a view-friendly wrapper over the receipt's
  # ActiveStorage blob. Every URL it exposes is HOST-RELATIVE (built with
  # only_path) AND permission-checked, pointing at
  # Admin::Reimbursements::ReceiptFilesController — anything that needs the
  # content itself (BatchProcessor's SharePoint offload) must call +bytes+
  # rather than hand a URL to a remote fetcher, which has no session.
  class Attachment
    attr_reader :attachment_id, :filename, :url, :size_bytes, :content_type, :thumbnail_url

    def initialize(attachment_id:, filename:, url:, size_bytes: 0, content_type: "",
                   thumbnail_url: nil, download_url: nil, blob: nil)
      @attachment_id = attachment_id
      @filename = filename
      @url = url
      @size_bytes = size_bytes
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

    # Falls back to the full image when no representation is available, so a
    # receipt still previews rather than showing nothing.
    def preview_url
      thumbnail_url.presence || (url if image?)
    end

    # Whether there is a thumbnail image to draw for this file. ActiveStorage
    # populates thumbnail_url for anything +representable?+, which covers PDFs
    # (first page, via poppler/mupdf) as well as images — so ask about the
    # capability, not the content type: +image?+ would skip PDF thumbnails.
    def previewable?
      preview_url.present?
    end

    # Whether the browser can render the file itself inside the page: images
    # directly, PDFs through the native viewer. Everything else
    # Attachment::ALLOWED_CONTENT_TYPES admits (Office documents, MuseScore /
    # MusicXML sheet music, MIDI) has to be downloaded instead.
    def inline_viewable?
      image? || pdf?
    end

    # The URL that always saves the file rather than displaying it, as opposed
    # to +url+, which displays it in place. The HTML download attribute would
    # not do the job on its own: browsers ignore it cross-origin.
    def download_url
      @download_url.presence || url
    end
  end
end
