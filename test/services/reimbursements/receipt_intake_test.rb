require "test_helper"

module Reimbursements
  class ReceiptIntakeTest < ActiveSupport::TestCase
    PDF_MAGIC = "%PDF-1.4\n".freeze
    EXE_MAGIC = "MZ\x90\x00\x03".freeze

    # A REAL HEVC-coded HEIC (400x260, EXIF "rotate 90 CW"): a renamed JPEG would
    # prove nothing, because libvips has to decode HEVC.
    HEIC_PATH = Rails.root.join("test/fixtures/files/reimbursements_receipt.heic")

    def heic_bytes = File.binread(HEIC_PATH)

    def upload(bytes, filename, type)
      ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new(bytes), filename: filename, type: type)
    end

    def heic_upload(filename: "IMG_1234.HEIC") = upload(heic_bytes, filename, "image/heic")

    # Any HEIC small enough to commit converts to well under 5 MB, so the ladder
    # is only reachable by moving the cap.
    def with_max_receipt_bytes(bytes)
      original = ExpenseForm::MAX_RECEIPT_BYTES
      silence_warnings { ExpenseForm.const_set(:MAX_RECEIPT_BYTES, bytes) }
      yield
    ensure
      silence_warnings { ExpenseForm.const_set(:MAX_RECEIPT_BYTES, original) }
    end

    # Stored 400x260 with a rotate-90 tag, so ignoring the rotation emits 400x260.
    test "an iPhone HEIC photo becomes an upright, untagged JPEG named .jpg" do
      receipt = ReceiptIntake.from_upload(heic_upload)
      assert receipt.ok?, receipt.error
      image = Vips::Image.new_from_buffer(receipt.bytes, "")

      assert_equal [ "image/jpeg", "IMG_1234.jpg" ], [ receipt.content_type, receipt.filename ],
                   "the filename ends up in the BACS email and SharePoint"
      assert_equal "jpegload_buffer", image.get("vips-loader")
      assert_equal 3, image.bands
      assert_equal [ 260, 400 ], [ image.width, image.height ], "upright (portrait), not as stored"
      assert_empty image.get_fields.grep(/orientation/), "a leftover tag would make viewers rotate it twice"
    end

    { [ "photo.heif", "image/heif" ] => "photo.jpg",
      [ "gallery-export.jpg", "application/octet-stream" ] => "gallery-export.jpg" }.each do |(given, declared), expected|
      test "a HEIC named #{given} is stored as #{expected}" do
        receipt = ReceiptIntake.from_bytes(bytes: heic_bytes, filename: given, declared_type: declared)

        assert receipt.ok?, receipt.error
        assert_equal [ expected, "image/jpeg" ], [ receipt.filename, receipt.content_type ]
      end
    end

    # A damaged photo must reach the submitter as a validation error, never a 500.
    {
      "IMG_9.HEIC" => [ "image/heic", -> { File.binread(Rails.root.join("test/fixtures/files/truncated_receipt.heic")) } ],
      "IMG_7.jpg" => [ "image/jpeg", -> { photo_with_gps(:jpegsave_buffer).byteslice(0, 40) } ]
    }.each do |name, (declared_type, bytes)|
      test "a corrupt #{name} is rejected with a friendly message instead of raising" do
        receipt = ReceiptIntake.from_bytes(bytes: instance_exec(&bytes), filename: name, declared_type: declared_type)

        assert_not receipt.ok?
        assert_match(/couldn't read #{Regexp.escape(name)}.*save it as a JPEG or PDF/, receipt.error)
        assert_nil receipt.bytes
      end
    end

    test "a file only claiming to be HEIC is still rejected by the sniffing" do
      receipt = ReceiptIntake.from_bytes(bytes: EXE_MAGIC, filename: "IMG_1.HEIC", declared_type: "image/heic")

      assert_not receipt.ok?
      assert_match(/must be a PDF or a photo/, receipt.error)
    end

    test "a PDF passes through byte-for-byte with its own name and type" do
      receipt = ReceiptIntake.from_upload(upload(PDF_MAGIC, "receipt.pdf", "application/pdf"))

      assert receipt.ok?, receipt.error
      assert_equal "receipt.pdf", receipt.filename
      assert_equal "application/pdf", receipt.content_type
      assert_equal PDF_MAGIC, receipt.bytes, "a PDF must reach finance exactly as the supplier issued it"
    end

    GPS_LATITUDE = "55/1 56/1 44/1".freeze

    # Built rather than committed, so the precondition proves the GPS tag is there.
    def photo_with_gps(saver, **opts)
      image = Vips::Image.black(64, 48).add(128).cast(:uchar).bandjoin([ 128, 128 ])
      image = image.mutate { |m| m.set_type!(GObject::GSTR_TYPE, "exif-ifd3-GPSLatitude", GPS_LATITUDE) }
      image.public_send(saver, **opts)
    end

    def metadata_fields(bytes)
      Vips::Image.new_from_buffer(bytes, "").get_fields.grep(/exif|xmp|iptc|orientation/i)
    end

    {
      "image/jpeg" => [ :jpegsave_buffer, "receipt.jpg", "jpegload_buffer" ],
      "image/png" => [ :pngsave_buffer, "receipt.png", "pngload_buffer" ],
      "image/webp" => [ :webpsave_buffer, "receipt.webp", "webpload_buffer" ]
    }.each do |content_type, (saver, filename, loader)|
      test "a #{content_type} receipt loses its EXIF, GPS and all, keeping its format" do
        bytes = photo_with_gps(saver)
        assert_includes metadata_fields(bytes).join(","), "GPS",
                        "precondition: the built #{content_type} must actually carry a GPS tag"

        receipt = ReceiptIntake.from_bytes(bytes: bytes, filename: filename, declared_type: content_type)

        assert receipt.ok?, receipt.error
        assert_equal content_type, receipt.content_type
        assert_equal filename, receipt.filename
        assert_equal loader, Vips::Image.new_from_buffer(receipt.bytes, "").get("vips-loader"),
                     "the format must survive the strip"
        assert_empty metadata_fields(receipt.bytes),
                     "no EXIF/XMP/IPTC may survive: GPS can hide in any of them"
        assert_not receipt.bytes.include?(GPS_LATITUDE),
                   "the coordinates must be gone from the bytes, not merely unindexed"
      end
    end

    test "stripping leaves the receipt itself readable at its original size" do
      bytes = photo_with_gps(:jpegsave_buffer, Q: 95)

      receipt = ReceiptIntake.from_bytes(bytes: bytes, filename: "receipt.jpg", declared_type: "image/jpeg")
      image = Vips::Image.new_from_buffer(receipt.bytes, "")

      assert_equal [ 64, 48 ], [ image.width, image.height ], "a strip must not resize a receipt that fits"
      assert_in_delta 128, image.getpoint(10, 10).first, 6, "the pixels must still be the receipt"
    end

    test "a sideways JPEG is turned upright before its orientation tag is dropped" do
      image = Vips::Image.black(80, 40).add(128).cast(:uchar).bandjoin([ 128, 128 ])
      image = image.mutate { |m| m.set_type!(GObject::GINT_TYPE, "orientation", 6) }
      bytes = image.jpegsave_buffer(Q: 90)

      receipt = ReceiptIntake.from_bytes(bytes: bytes, filename: "receipt.jpg", declared_type: "image/jpeg")
      stripped = Vips::Image.new_from_buffer(receipt.bytes, "")

      assert_equal [ 40, 80 ], [ stripped.width, stripped.height ], "should come out upright"
      assert_empty metadata_fields(receipt.bytes)
    end

    test "an oversized upload is rejected from its declared size, before anything is read" do
      file = upload(PDF_MAGIC, "huge.pdf", "application/pdf")
      def file.size = ExpenseForm::MAX_RECEIPT_BYTES + 1
      def file.read(*) = raise("must not read an oversized upload")

      receipt = ReceiptIntake.from_upload(file)

      assert_not receipt.ok?
      assert_equal "huge.pdf must be 5 MB or smaller.", receipt.error
    end

    test "a JPEG that lands over the cap is re-encoded down until it fits" do
      full_size = ReceiptIntake.from_upload(heic_upload).bytes.bytesize

      with_max_receipt_bytes(full_size - 1) do
        receipt = ReceiptIntake.from_upload(heic_upload)

        assert receipt.ok?, receipt.error
        assert_operator receipt.bytes.bytesize, :<=, full_size - 1
        assert_equal "image/jpeg", Marcel::MimeType.for(StringIO.new(receipt.bytes))
      end
    end

    # A cap above the HEIC (so it clears the size gate) but below every rung.
    test "a photo that will not fit even at the lowest quality is refused, not let through" do
      with_max_receipt_bytes(File.size(HEIC_PATH) + 100) do
        receipt = ReceiptIntake.from_upload(heic_upload)

        assert_not receipt.ok?
        assert_match(/still over 5 MB once converted/, receipt.error)
        assert_nil receipt.bytes
      end
    end
  end
end
