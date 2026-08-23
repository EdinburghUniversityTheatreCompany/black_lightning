module Reimbursements
  ##
  # The single gate every receipt passes through, whatever brought it in: the
  # producer's submission form, the finance/review receipt uploads, and the
  # mailbox poll's decoded Graph attachments. It checks the size, verifies the
  # ACTUAL bytes against the allow-list (never the declared content type alone,
  # see ReceiptContentType), and normalises anything we accept but don't want to
  # store as it arrived.
  #
  # Normalising means two things:
  #
  # * HEIC/HEIF, which iOS photographs default to, is converted to JPEG. That
  #   happens HERE, before anything is attached, so every downstream consumer
  #   sees an ordinary JPEG with no special-casing: the in-page viewer and
  #   thumbnail strip, the SharePoint receipt offload, and the receipts attached
  #   to the EUSA BACS email. Storing the HEIC and converting on read would need
  #   the same fix in each of those places, and would still hand HEIC to EUSA.
  #
  # * EVERY raster receipt has its metadata stripped. A phone photograph carries
  #   the coordinates it was taken at, which for a producer is usually their
  #   home, and those exact bytes go on to SharePoint and out as an email
  #   attachment to EUSA. The strip belongs at this gate for the same reason the
  #   conversion does: it is the one place every intake path passes through
  #   (the submission form, the finance/review uploads, the mailbox poll).
  #   Anything already re-encoded on the HEIC path is stripped by that save.
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
    # comfortably legible for finance; a typical phone photo never gets past
    # the first.
    JPEG_ATTEMPTS = [
      { quality: 80, limit: nil },
      { quality: 70, limit: 2400 },
      { quality: 60, limit: 1600 }
    ].freeze

    # The formats whose metadata is stripped in place, keeping the format. A PNG
    # screenshot of an invoice must stay a PNG: it is lossless text, and pushing
    # it through JPEG to save a few bytes would be the one visible cost of this.
    STRIPPED_SAVERS = {
      "image/jpeg" => :jpegsave_buffer,
      "image/png" => :pngsave_buffer,
      "image/webp" => :webpsave_buffer
    }.freeze

    # Re-encoding to drop the metadata can GROW a file — a phone's Q60 JPEG
    # saved back out at Q90 does — so the cap ladder applies here too. It starts
    # HIGHER than JPEG_ATTEMPTS on purpose: that path encodes a fresh capture for
    # the first time, whereas this one re-encodes something the producer already
    # compressed, so the first rung is chosen to be visually indistinguishable
    # rather than small. Nearly every receipt stops there.
    LOSSY_STRIP_ATTEMPTS = [
      { quality: 90, limit: nil },
      { quality: 80, limit: nil },
      { quality: 75, limit: 2400 },
      { quality: 70, limit: 1600 }
    ].freeze

    # PNG has no quality knob — it is lossless, so the only lever is the longest
    # edge. Repeating the quality rungs here would just re-encode identical bytes
    # three times before the first rung that can actually help.
    LOSSLESS_STRIP_ATTEMPTS = [
      { limit: nil },
      { limit: 2400 },
      { limit: 1600 }
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
        if STRIPPED_SAVERS.key?(type)
          strip_metadata(bytes: bytes, filename: filename, type: type)
        elsif ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(type)
          # PDFs only. Left byte-for-byte: finance and EUSA should hold the
          # supplier's invoice exactly as it was issued, and a PDF is a document
          # rather than a camera output — there is no location tag to remove.
          Receipt.new(filename: filename.to_s, content_type: type, bytes: bytes, error: nil)
        elsif ExpenseForm::CONVERTED_RECEIPT_TYPES.include?(type)
          to_jpeg(bytes: bytes, filename: filename)
        else
          rejected(filename, "#{display_name(filename)} must be a PDF or a photo (JPEG, PNG, WEBP or HEIC).")
        end
      end

      private

      def max_bytes = ExpenseForm::MAX_RECEIPT_BYTES

      # Drop the metadata from a raster receipt, keeping its format, its name and
      # its content type. The orientation is baked into the pixels first: the tag
      # that described it is about to be dropped with everything else, and
      # without that the receipt would come out sideways for whoever reviews it.
      #
      # The image is re-encoded rather than having its EXIF segment excised,
      # because a re-encode is the only version of this that is provably
      # complete. Coordinates can sit in EXIF GPS tags, inside XMP, inside a
      # vendor MakerNote, or inside the embedded EXIF thumbnail — which is
      # itself a small copy of the photo. Dropping the segments I happened to
      # think of would leave the ones I did not.
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

      # Convert a HEIC/HEIF photo to JPEG, renaming it to match: the filename
      # ends up in the BACS email and in SharePoint, so it must not claim to be
      # something the bytes aren't.
      def to_jpeg(bytes:, filename:)
        name = jpeg_filename(filename)
        image = flatten_for_jpeg(prepare(Vips::Image.new_from_buffer(bytes.to_s, "")))

        data = encode_within_cap(image, saver: :jpegsave_buffer, attempts: JPEG_ATTEMPTS)
        return rejected(name, over_cap_message(filename, from_heic: true)) if data.nil?

        Receipt.new(filename: name, content_type: JPEG_CONTENT_TYPE, bytes: data, error: nil)
      rescue StandardError => e
        unreadable(name, filename, e)
      end

      # One rejection for every way libvips can fail to produce an image: a
      # truncated or damaged upload, and also a libvips built WITHOUT HEIF
      # support ("class heifload not found"). The message is logged so that
      # environment problem stays diagnosable rather than looking like a stream
      # of damaged uploads.
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

      # Walk the ladder until an encoding fits under the cap; nil when none does.
      def encode_within_cap(image, saver:, attempts:)
        attempts.each do |attempt|
          data = encode(image, saver: saver, **attempt)
          return data if data.bytesize <= max_bytes
        end
        nil
      end

      # Applies EXIF orientation — iPhone HEICs carry rotation metadata, and a
      # sideways receipt is needless work for whoever reviews it. Done for every
      # format, because the tag is about to be stripped along with the rest.
      def prepare(image)
        raise ConversionError, "#{image.width}x#{image.height} is too many pixels" if
          image.width * image.height > MAX_PIXELS

        image.autorot
      end

      # Only for a JPEG target: it carries neither an alpha channel nor CMYK
      # sensibly. PNG and WEBP keep their bands as they arrived — flattening a
      # transparent screenshot onto white here would be a visible change to a
      # receipt, made for no reason, since neither format needs it.
      def flatten_for_jpeg(image)
        image = image.flatten(background: 255) if image.has_alpha?
        image.colourspace(:srgb)
      end

      # strip: true drops the metadata, including the orientation tag we have
      # just baked into the pixels — leaving it would make every viewer rotate
      # the receipt a second time.
      #
      # +quality+ is absent for PNG, which has no such knob (see
      # LOSSLESS_STRIP_ATTEMPTS); passing Q: to pngsave_buffer would be ignored
      # unless it were also quantising to a palette, which would be a real
      # quality loss smuggled in under a metadata strip.
      def encode(image, saver:, limit:, quality: nil)
        candidate = limit ? image.thumbnail_image(limit, height: limit, size: :down) : image
        options = { strip: true }
        options[:Q] = quality if quality
        options[:optimize_coding] = true if saver == :jpegsave_buffer
        candidate.public_send(saver, **options)
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
