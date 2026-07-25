module Reimbursements
  ##
  # A file attached to an expense: a view-friendly wrapper over the receipt's
  # ActiveStorage blob. The URLs it exposes are app-authenticated paths, so
  # nothing outside the app can fetch them; consumers that need the content
  # itself (AiChecker, BatchProcessor's SharePoint offload) call +bytes+.
  class Attachment
    attr_reader :attachment_id, :filename, :url, :size_bytes, :content_type, :thumbnail_url

    def initialize(attachment_id:, filename:, url:, size_bytes: 0, content_type: "",
                   thumbnail_url: nil, inline_url: nil, download_url: nil, blob: nil)
      @attachment_id = attachment_id
      @filename = filename
      @url = url
      @size_bytes = size_bytes
      @content_type = content_type
      @thumbnail_url = thumbnail_url
      @inline_url = inline_url
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

    # The URL to point an in-page <img>/<iframe> at: the same bytes as +url+,
    # but proxied through the app with an explicit inline disposition. Two
    # reasons not to reuse +url+: it redirects to the storage host (so the frame
    # navigates cross-origin, which the app's CSP frame-src does not allow), and
    # it leaves the disposition unset. Falls back to +url+ for wrappers built
    # without one.
    def inline_url
      @inline_url.presence || url
    end

    # The URL that always saves the file rather than displaying it. The HTML
    # download attribute would not do: browsers ignore it cross-origin, and in
    # production +url+ redirects to the storage host.
    def download_url
      @download_url.presence || url
    end
  end
end
