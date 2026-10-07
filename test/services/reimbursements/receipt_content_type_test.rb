require "test_helper"

module Reimbursements
  class ReceiptContentTypeTest < ActiveSupport::TestCase
    PDF_MAGIC = "%PDF-1.4\n".freeze

    # A hand-crafted "receipts[]=x" post sends a String: it has #size but no #read,
    # so it passes the size check and 500s on read. Same for a nested hash or array.
    test "uploads_from drops receipts params that are not uploaded files" do
      real = ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new(PDF_MAGIC),
                                                    filename: "receipt.pdf",
                                                    type: "application/pdf")

      assert_equal [ real ], ReceiptContentType.uploads_from(
        [ "not-a-file", real, %w[a b], StringIO.new(PDF_MAGIC), { "tempfile" => "x" } ]
      )
      assert_empty ReceiptContentType.uploads_from("not-a-file")
      assert_empty ReceiptContentType.uploads_from(nil)
      assert_empty ReceiptContentType.uploads_from([ "", nil ])
    end
  end
end
