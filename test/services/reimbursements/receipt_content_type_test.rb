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

    # S10: a hand-crafted "receipts[]=something" post sends a String, which has
    # #size (so it sails past the byte check the intake paths do first) but no
    # #read, so allowed_upload? raised an unrescued NoMethodError — a 500 any
    # authenticated producer could trigger. Same for a nested hash or array,
    # which Rails also happily parses out of a multipart body.
    test "uploads_from drops receipts params that are not uploaded files" do
      real = ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new(PDF_MAGIC),
                                                    filename: "receipt.pdf",
                                                    type: "application/pdf")

      assert_equal [ real ], ReceiptContentType.uploads_from([ "not-a-file", real, %w[a b] ])
      assert_empty ReceiptContentType.uploads_from("not-a-file")
      assert_empty ReceiptContentType.uploads_from(nil)
      assert_empty ReceiptContentType.uploads_from([ "", nil ])
    end

    test "uploaded_file? rejects a String that only looks file-shaped" do
      assert_not ReceiptContentType.uploaded_file?("receipt.pdf"), "a String answers #size but not #read"
      assert_not ReceiptContentType.uploaded_file?(StringIO.new(PDF_MAGIC)), "no original_filename"
      assert_not ReceiptContentType.uploaded_file?({ "tempfile" => "x" }), "a nested hash is not an upload"
      assert ReceiptContentType.uploaded_file?(
        ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new(PDF_MAGIC),
                                               filename: "receipt.pdf", type: "application/pdf")
      )
    end
  end
end
