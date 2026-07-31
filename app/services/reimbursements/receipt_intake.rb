module Reimbursements
  ##
  # The single gate every receipt passes through, whatever brought it in: the
  # producer's submission form, the finance/review receipt uploads, and the
  # mailbox poll's decoded Graph attachments. It checks the size, verifies the
  # ACTUAL bytes against the allow-list (never the declared content type alone,
  # see ReceiptContentType), and normalises anything we accept but don't want to
  # store as it arrived.
  #
  # Today that means HEIC/HEIF, which iOS photographs default to. Conversion to
  # JPEG happens HERE, before anything is attached, so every downstream consumer
  # sees an ordinary JPEG with no special-casing: the in-page viewer and thumbnail
  # strip, the SharePoint receipt offload, and the receipts attached to the EUSA
  # BACS email. Storing the HEIC and converting on read would need the same fix
  # in each of those places, and would still hand HEIC to EUSA.
  #
  # Nothing here ever raises at a caller: an unreadable photo comes back as a
  # Receipt carrying a friendly #error, which each intake path reports through
  # its own normal validation/flash path.
  module ReceiptIntake
    JPEG_CONTENT_TYPE = "image/jpeg".freeze

    # One vetted receipt, ready to attach (or to send to the extractor), or a
    # rejection carrying the message to show whoever sent it.
    Receipt = Data.define(:filename, :content_type, :bytes, :error) do
      def ok? = error.nil?

      # The keyword arguments Store#attach_receipt! and the extractor both take.
      def to_attachment = { filename: filename, content_type: content_type, bytes: bytes }
    end

    # Conversion targets, tried in order until one fits under MAX_RECEIPT_BYTES.
    # HEIC is roughly half the size of the equivalent JPEG, so a *compliant*
    # HEIC can convert into a JPEG over the cap, and that cap is not cosmetic:
    # a batch mails every receipt in it as an attachment. Rather than reject a
    # photo the producer did nothing wrong with, step the quality (and then the
    # longest edge) down until it fits. Even the last rung leaves a till receipt
    # comfortably legible for finance and for the AI check; a typical phone
    # photo never gets past the first.
    JPEG_ATTEMPTS = [
      { quality: 80, limit: nil },
      { quality: 70, limit: 2400 },
      { quality: 60, limit: 1600 }
    ].freeze

    # Decompression guard: HEIC packs so well that a file inside the 5 MB cap
    # can still decode to an absurd number of pixels. No real receipt photo is
    # anywhere near this, so refuse rather than hand libvips the allocation.
    MAX_PIXELS = 100_000_000

    # Raised internally when the photo can't be turned into a JPEG; never
    # escapes this module.
    ConversionError = Class.new(StandardError)

    class << self
      # The uploads in a `receipts[]` param, each vetted. Anything that isn't
      # actually an uploaded file is dropped first (see uploads_from), so the
      # result is one Receipt per real file, in order.
      def from_params(value)
        ReceiptContentType.uploads_from(value).map { |file| from_upload(file) }
      end

      # For an ActionDispatch::Http::UploadedFile-like object. The size is
      # checked from the upload's own #size before anything is read, so an
      # oversized file is never pulled into memory just to be rejected for size.
      def from_upload(file)
        return rejected(file.original_filename, too_large_message(file.original_filename)) if file.size > max_bytes

        from_bytes(bytes: file.read, filename: file.original_filename, declared_type: file.content_type)
      ensure
        file.rewind if file.respond_to?(:rewind)
      end

      # For an already-in-memory receipt (the mailbox poll's decoded Graph
      # attachment bytes).
      def from_bytes(bytes:, filename:, declared_type:)
        return rejected(filename, too_large_message(filename)) if bytes.to_s.bytesize > max_bytes

        type = ReceiptContentType.sniff(bytes: bytes, filename: filename, declared_type: declared_type)
        if ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(type)
          Receipt.new(filename: filename.to_s, content_type: type, bytes: bytes, error: nil)
        elsif ExpenseForm::CONVERTED_RECEIPT_TYPES.include?(type)
          to_jpeg(bytes: bytes, filename: filename)
        else
          rejected(filename, "#{display_name(filename)} must be a PDF or a photo (JPEG, PNG, WEBP or HEIC).")
        end
      end

      private

      def max_bytes = ExpenseForm::MAX_RECEIPT_BYTES

      # Convert a HEIC/HEIF photo to JPEG, renaming it to match: the filename
      # ends up in the BACS email and in SharePoint, so it must not claim to be
      # something the bytes aren't.
      def to_jpeg(bytes:, filename:)
        name = jpeg_filename(filename)
        image = prepare(Vips::Image.new_from_buffer(bytes.to_s, ""))

        JPEG_ATTEMPTS.each do |attempt|
          data = encode(image, **attempt)
          next if data.bytesize > max_bytes

          return Receipt.new(filename: name, content_type: JPEG_CONTENT_TYPE, bytes: data, error: nil)
        end

        rejected(name, "#{display_name(filename)} is still over 5 MB once converted from a HEIC photo " \
                       "to a JPEG. Please save it as a smaller JPEG or PDF and try again.")
      rescue StandardError => e
        # Includes Vips::Error, which is also what a libvips built WITHOUT HEIF
        # support raises ("class heifload not found") — log the message so that
        # environment problem is diagnosable rather than looking like a stream
        # of damaged uploads.
        Rails.logger.error("Reimbursements receipt HEIC conversion failed for " \
                           "#{filename.inspect}: #{e.class}: #{e.message}")
        rejected(name, "We couldn't read #{display_name(filename)}. It may be damaged, or your " \
                       "device saved it in a format we can't open. Please save it as a JPEG or " \
                       "PDF and try again.")
      end

      # Applies EXIF orientation (iPhone HEICs carry rotation metadata, and a
      # sideways receipt is both annoying for finance and worse for the AI
      # check), then flattens any transparency onto white and normalises the
      # colourspace, because JPEG carries neither an alpha channel nor CMYK
      # sensibly.
      def prepare(image)
        raise ConversionError, "#{image.width}x#{image.height} is too many pixels" if
          image.width * image.height > MAX_PIXELS

        image = image.autorot
        image = image.flatten(background: 255) if image.has_alpha?
        image.colourspace(:srgb)
      end

      # strip: true drops the metadata, including the orientation tag we have
      # just baked into the pixels — leaving it would make every viewer rotate
      # the receipt a second time.
      def encode(image, quality:, limit:)
        candidate = limit ? image.thumbnail_image(limit, height: limit, size: :down) : image
        candidate.jpegsave_buffer(Q: quality, strip: true, optimize_coding: true)
      end

      # IMG_1234.HEIC -> IMG_1234.jpg. Any other image extension is replaced too
      # (a HEIC named .jpg by some gallery app shouldn't become "photo.jpg.jpg").
      def jpeg_filename(filename)
        base = File.basename(filename.to_s.strip).sub(/\.(heic|heif|jpe?g|png|webp)\z/i, "")
        base = "receipt" if base.blank?
        "#{base}.jpg"
      end

      def too_large_message(filename)
        "#{display_name(filename)} must be 5 MB or smaller."
      end

      def display_name(filename)
        filename.to_s.strip.presence || "That file"
      end

      def rejected(filename, error)
        Receipt.new(filename: filename.to_s, content_type: nil, bytes: nil, error: error)
      end
    end
  end
end
