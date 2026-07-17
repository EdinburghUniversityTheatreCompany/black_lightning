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

    # For an already-in-memory receipt (mailbox poll's decoded Graph
    # attachment bytes).
    def allowed?(bytes:, filename:, declared_type:)
      ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(sniff(bytes: bytes, filename: filename, declared_type: declared_type))
    end

    # For an ActionDispatch::Http::UploadedFile-like object still to be read.
    # Rewinds afterward so a caller can still read the full file itself
    # (attaching it, extracting it) without getting back an empty string from
    # a pointer left at EOF.
    def allowed_upload?(file)
      allowed?(bytes: file.read, filename: file.original_filename, declared_type: file.content_type)
    ensure
      file.rewind
    end

    def sniff(bytes:, filename:, declared_type:)
      Marcel::MimeType.for(StringIO.new(bytes.to_s), name: filename.to_s, declared_type: declared_type.to_s)
    end
  end
end
