require "test_helper"

module Reimbursements
  class ReceiptIntakeTest < ActiveSupport::TestCase
    PDF_MAGIC = "%PDF-1.4\n".freeze
    EXE_MAGIC = "MZ\x90\x00\x03".freeze

    # test/fixtures/files/reimbursements_receipt.heic is a REAL HEIC: HEVC-coded
    # image data in a HEIF container, carrying EXIF, produced with libheif's
    # heif-enc from a 400x260 landscape image whose EXIF said "rotate 90 CW".
    # A renamed JPEG would prove nothing here — the whole point is that libvips
    # has to decode HEVC.
    HEIC_PATH = Rails.root.join("test/fixtures/files/reimbursements_receipt.heic")

    def heic_bytes = File.binread(HEIC_PATH)

    def upload(bytes, filename, type)
      ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new(bytes), filename: filename, type: type)
    end

    def heic_upload(filename: "IMG_1234.HEIC") = upload(heic_bytes, filename, "image/heic")

    # MAX_RECEIPT_BYTES is 5 MB and any HEIC small enough to commit converts to
    # well under it, so the only way to exercise the "converted result is over
    # the cap" ladder is to move the cap.
    def with_max_receipt_bytes(bytes)
      original = ExpenseForm::MAX_RECEIPT_BYTES
      silence_warnings { ExpenseForm.const_set(:MAX_RECEIPT_BYTES, bytes) }
      yield
    ensure
      silence_warnings { ExpenseForm.const_set(:MAX_RECEIPT_BYTES, original) }
    end

    test "an iPhone HEIC photo is converted to JPEG and renamed" do
      receipt = ReceiptIntake.from_upload(heic_upload)

      assert receipt.ok?, receipt.error
      assert_equal "image/jpeg", receipt.content_type
      assert_equal "IMG_1234.jpg", receipt.filename, "the filename ends up in the BACS email and SharePoint"
      assert_equal "image/jpeg", Marcel::MimeType.for(StringIO.new(receipt.bytes)),
                   "the stored bytes must actually BE a JPEG"
    end

    test "the converted JPEG is a readable image, not just JPEG-shaped bytes" do
      receipt = ReceiptIntake.from_upload(heic_upload)
      image = Vips::Image.new_from_buffer(receipt.bytes, "")

      assert_equal "jpegload_buffer", image.get("vips-loader")
      assert_operator image.width, :>, 0
      assert_equal 3, image.bands
    end

    # The fixture's pixels are stored 400x260 (landscape) with metadata saying
    # rotate 90 CW, so an implementation that ignored the rotation would emit a
    # 400x260 JPEG. Finance would otherwise get a sideways receipt, which reads
    # worse.
    test "EXIF orientation is applied, and not left behind to be applied twice" do
      receipt = ReceiptIntake.from_upload(heic_upload)
      image = Vips::Image.new_from_buffer(receipt.bytes, "")

      assert_equal [ 260, 400 ], [ image.width, image.height ],
                   "the photo should come out upright (portrait), not as stored"
      assert_empty image.get_fields.grep(/orientation/),
                   "a leftover orientation tag would make viewers rotate it a second time"
    end

    test "a HEIF declared type takes the same path" do
      receipt = ReceiptIntake.from_bytes(bytes: heic_bytes, filename: "photo.heif", declared_type: "image/heif")

      assert receipt.ok?, receipt.error
      assert_equal "photo.jpg", receipt.filename
      assert_equal "image/jpeg", receipt.content_type
    end

    test "a HEIC whose name already claims another image extension is not double-suffixed" do
      receipt = ReceiptIntake.from_bytes(bytes: heic_bytes, filename: "gallery-export.jpg",
                                         declared_type: "application/octet-stream")

      assert receipt.ok?, receipt.error
      assert_equal "gallery-export.jpg", receipt.filename
      assert_equal "image/jpeg", receipt.content_type
    end

    # A truncated photo (a half-finished upload, a damaged file) must reach the
    # submitter as a normal validation error, never a 500.
    test "a corrupt HEIC is rejected with a friendly message instead of raising" do
      truncated = File.binread(Rails.root.join("test/fixtures/files/truncated_receipt.heic"))

      receipt = ReceiptIntake.from_bytes(bytes: truncated, filename: "IMG_9.HEIC", declared_type: "image/heic")

      assert_not receipt.ok?
      assert_match(/couldn't read IMG_9\.HEIC/, receipt.error)
      assert_match(/save it as a JPEG or PDF/, receipt.error)
      assert_nil receipt.bytes
    end

    # The whole point of sniffing: claiming to be a HEIC must not be enough to
    # get anything near the converter.
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
      assert_equal PDF_MAGIC, receipt.bytes
    end

    test "an ordinary photo is untouched by the conversion path" do
      png = File.binread(Rails.root.join("test/fixtures/files/renderable_receipt.png"))

      receipt = ReceiptIntake.from_upload(upload(png, "receipt.png", "image/png"))

      assert receipt.ok?, receipt.error
      assert_equal "receipt.png", receipt.filename
      assert_equal "image/png", receipt.content_type
      assert_equal png, receipt.bytes, "a PNG must not be re-encoded"
    end

    test "an oversized upload is rejected from its declared size, before anything is read" do
      file = upload(PDF_MAGIC, "huge.pdf", "application/pdf")
      def file.size = ExpenseForm::MAX_RECEIPT_BYTES + 1
      def file.read(*) = raise("must not read an oversized upload")

      receipt = ReceiptIntake.from_upload(file)

      assert_not receipt.ok?
      assert_equal "huge.pdf must be 5 MB or smaller.", receipt.error
    end

    # HEIC is roughly half the size of the equivalent JPEG, so a receipt inside
    # the cap can convert into a JPEG over it. Nothing oversized may be let
    # through: a batch mails every receipt as an attachment.
    test "a JPEG that lands over the cap is re-encoded down until it fits" do
      full_size = ReceiptIntake.from_upload(heic_upload).bytes.bytesize

      with_max_receipt_bytes(full_size - 1) do
        receipt = ReceiptIntake.from_upload(heic_upload)

        assert receipt.ok?, receipt.error
        assert_operator receipt.bytes.bytesize, :<=, full_size - 1
        assert_equal "image/jpeg", Marcel::MimeType.for(StringIO.new(receipt.bytes))
      end
    end

    # A cap above the HEIC itself (so it clears the input size gate) but below
    # every rung of the ladder.
    test "a photo that will not fit even at the lowest quality is refused, not let through" do
      with_max_receipt_bytes(File.size(HEIC_PATH) + 100) do
        receipt = ReceiptIntake.from_upload(heic_upload)

        assert_not receipt.ok?
        assert_match(/still over 5 MB once converted/, receipt.error)
        assert_nil receipt.bytes
      end
    end

    test "from_params vets each upload and drops anything that is not a file" do
      receipts = ReceiptIntake.from_params([ "not-a-file", heic_upload, upload(EXE_MAGIC, "x.pdf", "application/pdf") ])

      assert_equal 2, receipts.size
      assert_equal [ true, false ], receipts.map(&:ok?)
      assert_equal "IMG_1234.jpg", receipts.first.filename
    end

    test "to_attachment hands the store exactly the keywords attach_receipt! takes" do
      attachment = ReceiptIntake.from_upload(heic_upload).to_attachment

      assert_equal %i[filename content_type bytes], attachment.keys
    end
  end
end
