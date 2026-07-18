module Reimbursements
  ##
  # The PORO-compat identifier shim shared by every reimbursements AR model:
  # callers treat record ids as opaque strings (they were Airtable "rec…"
  # ids). One seam to delete when the post-flip cleanup retires the
  # string-id vocabulary.
  module RecordId
    def record_id = id&.to_s
  end
end
