module Reimbursements
  ##
  # Verifies a receipt's ACTUAL content matches one of ExpenseForm's allowed
  # types via Marcel's magic-byte sniffing, rather than trusting the
  # client/sender-declared content_type alone — every receipt-intake path
  # (the portal form, the finance edit/review receipt uploads, the mailbox
  # poll) previously accepted whatever content_type the browser or the email's
  # attachment metadata claimed, which is trivially spoofed (rename a binary
  # to "receipt.pdf" and declare application/pdf). Mirrors the same
  # Marcel::MimeType.for(declared_type:, name:) pattern the app's Attachment
  # model already uses for every other upload.
  module ReceiptContentType
    module_function

    # The uploads in a `receipts[]` param, with anything that is not actually an
    # uploaded file dropped. Rails parses whatever a multipart body contains, so a
    # hand-crafted post can put a bare String (or a nested array/hash) in there.
    # A String is the dangerous shape: it answers #size, so it sailed past the
    # byte check every intake path does first, and then #allowed_upload?'s #read
    # raised an unrescued NoMethodError — a 500 available to any authenticated
    # producer. Dropping it here turns that into the ordinary "no usable receipt
    # files" path.
    def uploads_from(value)
      Array(value).compact_blank.select { |file| uploaded_file?(file) }
    end

    # Duck-types the ActionDispatch::Http::UploadedFile surface every receipt
    # intake path actually uses: the size check, the sniff (#read), and the error
    # messages / attach (#original_filename, #content_type). Deliberately does NOT
    # demand #rewind: the oversized branch short-circuits before anything is read,
    # so a value that never gets rewound is still a usable upload for that path.
    # #read is the discriminator that catches the reported String case.
    def uploaded_file?(value)
      %i[read size original_filename content_type].all? { |message| value.respond_to?(message) }
    end

    # The detected type of these bytes. ReceiptIntake decides what to do with
    # it: store it as it is, convert it (HEIC), or reject it.
    def sniff(bytes:, filename:, declared_type:)
      Marcel::MimeType.for(StringIO.new(bytes.to_s), name: filename.to_s, declared_type: declared_type.to_s)
    end
  end
end
