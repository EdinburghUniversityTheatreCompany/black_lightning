module Reimbursements
  ##
  # Expense status labels, mirroring the Airtable single-select exactly
  # (bedlam-bacs owns the state machine; the portal only ever writes Pending).
  module Status
    PENDING = "Pending".freeze
    APPROVED = "Approved".freeze
    SUBMITTED = "Submitted".freeze
    PAID = "Paid".freeze
    REJECTED = "Rejected".freeze

    BADGE_VARIANTS = {
      PENDING => :warning,
      APPROVED => :info,
      SUBMITTED => :primary,
      PAID => :success,
      REJECTED => :danger
    }.freeze

    def self.all
      BADGE_VARIANTS.keys
    end

    def self.badge_variant(status)
      BADGE_VARIANTS.fetch(status, :secondary)
    end
  end
end
