module Reimbursements
  ##
  # The one gate every receipt passes through (producer form, finance and review
  # uploads, mailbox poll). Checks the size, verifies the ACTUAL bytes against the
  # allow-list (see ReceiptContentType), converts HEIC to JPEG and strips the
  # metadata from every raster image. Done here so the viewer, the SharePoint
  # offload and the EUSA email never see HEIC, or the GPS position a phone photo
  # carries (usually the producer's home).
  #
  # Never raises at a caller: an unreadable photo comes back as a Receipt with a
  # friendly #error.
  module ReceiptIntake
    JPEG_CONTENT_TYPE = "image/jpeg".freeze

    # One vetted receipt, ready to attach, or a rejection carrying the message to
    # show whoever sent it.
    Receipt = Data.define(:filename, :content_type, :bytes, :error) do
      def ok? = error.nil?

      # The keyword arguments Store#attach_receipt! takes.
      def to_attachment = { filename: filename, content_type: content_type, bytes: bytes }
    end

    # HEIC is about half the size of the JPEG, so a compliant HEIC can convert to
    # over the cap, and a batch mails every receipt. Step the quality, then the
    # longest edge, down until it fits rather than reject a photo the producer did
    # nothing wrong with. Even the last rung leaves a till receipt legible.
    JPEG_ATTEMPTS = [
      { quality: 80, limit: nil },
      { quality: 70, limit: 2400 },
      { quality: 60, limit: 1600 }
    ].freeze

    # Keeps the format: a PNG screenshot of an invoice is lossless text.
    STRIPPED_SAVERS = {
      "image/jpeg" => :jpegsave_buffer,
      "image/png" => :pngsave_buffer,
      "image/webp" => :webpsave_buffer
    }.freeze

    # Re-encoding can GROW a file (a phone's Q60 JPEG saved at Q90 does), so the
    # cap ladder applies here too. Rung one starts higher than JPEG_ATTEMPTS
    # because the input is already compressed.
    LOSSY_STRIP_ATTEMPTS = [
      { quality: 90, limit: nil },
      { quality: 80, limit: nil },
      { quality: 75, limit: 2400 },
      { quality: 70, limit: 1600 }
    ].freeze

    # PNG is lossless, so the only lever is the longest edge.
    LOSSLESS_STRIP_ATTEMPTS = [
      { limit: nil },
      { limit: 2400 },
      { limit: 1600 }
    ].freeze

    # Decompression guard: HEIC inside the 5 MB cap can decode to an absurd pixel
    # count.
    MAX_PIXELS = 100_000_000

    # Never escapes this module.
    ConversionError = Class.new(StandardError)

    class << self
      def from_params(value)
        ReceiptContentType.uploads_from(value).map { |file| from_upload(file) }
      end

      # Size is checked from #size before anything is read, so an oversized file
      # is never pulled into memory.
      def from_upload(file)
        return rejected(file.original_filename, too_large_message(file.original_filename)) if file.size > max_bytes

        from_bytes(bytes: file.read, filename: file.original_filename, declared_type: file.content_type)
      ensure
        file.rewind if file.respond_to?(:rewind)
      end

      def from_bytes(bytes:, filename:, declared_type:)
        return rejected(filename, too_large_message(filename)) if bytes.to_s.bytesize > max_bytes

        type = ReceiptContentType.sniff(bytes: bytes, filename: filename, declared_type: declared_type)
        if STRIPPED_SAVERS.key?(type)
          strip_metadata(bytes: bytes, filename: filename, type: type)
        elsif ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(type)
          # PDFs only, byte-for-byte, so EUSA holds the invoice exactly as issued.
          Receipt.new(filename: filename.to_s, content_type: type, bytes: bytes, error: nil)
        elsif ExpenseForm::CONVERTED_RECEIPT_TYPES.include?(type)
          to_jpeg(bytes: bytes, filename: filename)
        else
          rejected(filename, "#{display_name(filename)} must be a PDF or a photo (JPEG, PNG, WEBP or HEIC).")
        end
      end

      private

      def max_bytes = ExpenseForm::MAX_RECEIPT_BYTES

      # Re-encoded rather than having its EXIF segment excised: GPS also hides in
      # XMP, MakerNote and the embedded thumbnail, so only a re-encode is
      # provably complete.
      def strip_metadata(bytes:, filename:, type:)
        name = filename.to_s
        image = prepare(Vips::Image.new_from_buffer(bytes.to_s, ""))
        image = flatten_for_jpeg(image) if type == JPEG_CONTENT_TYPE

        data = encode_within_cap(image, saver: STRIPPED_SAVERS.fetch(type), attempts: strip_attempts(type))
        return rejected(name, over_cap_message(filename)) if data.nil?

        Receipt.new(filename: name, content_type: type, bytes: data, error: nil)
      rescue StandardError => e
        unreadable(name, filename, e)
      end

      def strip_attempts(type)
        type == "image/png" ? LOSSLESS_STRIP_ATTEMPTS : LOSSY_STRIP_ATTEMPTS
      end

      def to_jpeg(bytes:, filename:)
        name = jpeg_filename(filename)
        image = flatten_for_jpeg(prepare(Vips::Image.new_from_buffer(bytes.to_s, "")))

        data = encode_within_cap(image, saver: :jpegsave_buffer, attempts: JPEG_ATTEMPTS)
        return rejected(name, over_cap_message(filename, from_heic: true)) if data.nil?

        Receipt.new(filename: name, content_type: JPEG_CONTENT_TYPE, bytes: data, error: nil)
      rescue StandardError => e
        unreadable(name, filename, e)
      end

      # Also covers a libvips built without HEIF support; logged so that stays
      # diagnosable.
      def unreadable(name, filename, error)
        Rails.logger.error("Reimbursements receipt processing failed for " \
                           "#{filename.inspect}: #{error.class}: #{error.message}")
        rejected(name, "We couldn't read #{display_name(filename)}. It may be damaged, or your " \
                       "device saved it in a format we can't open. Please save it as a JPEG or " \
                       "PDF and try again.")
      end

      def over_cap_message(filename, from_heic: false)
        converted = from_heic ? " once converted from a HEIC photo to a JPEG" : ""
        "#{display_name(filename)} is still over 5 MB#{converted}. Please save it as a smaller " \
          "JPEG or PDF and try again."
      end

      def encode_within_cap(image, saver:, attempts:)
        attempts.each do |attempt|
          data = encode(image, saver: saver, **attempt)
          return data if data.bytesize <= max_bytes
        end
        nil
      end

      # Bakes the EXIF orientation into the pixels before the tag is stripped, or
      # the receipt comes out sideways.
      def prepare(image)
        raise ConversionError, "#{image.width}x#{image.height} is too many pixels" if
          image.width * image.height > MAX_PIXELS

        image.autorot
      end

      # JPEG targets only: flattening a transparent PNG/WEBP onto white would
      # visibly change a receipt.
      def flatten_for_jpeg(image)
        image = image.flatten(background: 255) if image.has_alpha?
        image.colourspace(:srgb)
      end

      # strip: true also drops the orientation tag just baked in, which viewers
      # would otherwise apply twice. No quality for PNG: Q reaches pngsave only
      # when quantising to a palette, which is real loss smuggled in.
      def encode(image, saver:, limit:, quality: nil)
        candidate = limit ? image.thumbnail_image(limit, height: limit, size: :down) : image
        options = { strip: true }
        options[:Q] = quality if quality
        options[:optimize_coding] = true if saver == :jpegsave_buffer
        candidate.public_send(saver, **options)
      end

      # The name must match the bytes: it ends up in the BACS email and SharePoint.
      # A HEIC already named .jpg must not become .jpg.jpg.
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
