module Reimbursements
  ##
  # Sniffs a receipt's ACTUAL type with Marcel instead of trusting the declared
  # content type, which is trivially spoofed. Every intake path routes through here.
  module ReceiptContentType
    module_function

    # Drops anything in a `receipts[]` param that is not an uploaded file. A
    # hand-crafted post can put a bare String there: it answers #size but not
    # #read, so it passes the size check and 500s on read.
    def uploads_from(value)
      Array(value).compact_blank.select { |file| uploaded_file?(file) }
    end

    # Deliberately does NOT demand #rewind: the oversized branch returns before
    # anything is read.
    def uploaded_file?(value)
      %i[read size original_filename content_type].all? { |message| value.respond_to?(message) }
    end

    def sniff(bytes:, filename:, declared_type:)
      Marcel::MimeType.for(StringIO.new(bytes.to_s), name: filename.to_s, declared_type: declared_type.to_s)
    end
  end
end
