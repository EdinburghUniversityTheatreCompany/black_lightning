require "test_helper"

module Reimbursements
  class ReceiptContentTypeTest < ActiveSupport::TestCase
    PDF_MAGIC = "%PDF-1.4\n".freeze
    PNG_MAGIC = "\x89PNG\r\n\x1a\n".freeze
    EXE_MAGIC = "MZ\x90\x00\x03".freeze

    test "accepts a real PDF whose declared type matches its actual bytes" do
      assert ReceiptContentType.allowed?(bytes: PDF_MAGIC, filename: "receipt.pdf",
                                         declared_type: "application/pdf")
    end

    test "accepts a real PNG whose declared type matches its actual bytes" do
      assert ReceiptContentType.allowed?(bytes: PNG_MAGIC, filename: "receipt.png",
                                         declared_type: "image/png")
    end

    test "rejects an executable disguised with a PDF filename and declared content_type" do
      assert_not ReceiptContentType.allowed?(bytes: EXE_MAGIC, filename: "receipt.pdf",
                                             declared_type: "application/pdf")
    end

    test "sniff reports the actual detected type regardless of what was declared" do
      assert_equal "application/x-msdownload",
                   ReceiptContentType.sniff(bytes: EXE_MAGIC, filename: "receipt.pdf",
                                            declared_type: "application/pdf")
    end

    test "allowed_upload? reads and rewinds an uploaded file so it can still be read afterward" do
      io = StringIO.new(PDF_MAGIC)
      file = ActionDispatch::Http::UploadedFile.new(tempfile: io, filename: "receipt.pdf",
                                                     type: "application/pdf")

      assert ReceiptContentType.allowed_upload?(file)
      assert_equal PDF_MAGIC, file.read, "the file must be rewound so a later read gets the full content"
    end

    test "allowed_upload? rewinds even when the sniffed type is rejected" do
      io = StringIO.new(EXE_MAGIC)
      file = ActionDispatch::Http::UploadedFile.new(tempfile: io, filename: "receipt.pdf",
                                                     type: "application/pdf")

      assert_not ReceiptContentType.allowed_upload?(file)
      assert_equal EXE_MAGIC, file.read
    end
  end
end
