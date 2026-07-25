module Reimbursements
  ##
  # Every reimbursements AR model exposes its id as an opaque string: the
  # store's public API, the params it takes and the views all speak record ids
  # as strings, so nothing above the store has to know they are integer PKs.
  module RecordId
    def record_id = id&.to_s
  end
end
