module Reimbursements
  ##
  # Expense status labels, stored as the strings finance reads.
  module Status
    DRAFT = "Draft".freeze
    PENDING = "Pending".freeze
    APPROVED = "Approved".freeze
    SUBMITTED = "Submitted".freeze
    PAID = "Paid".freeze
    REJECTED = "Rejected".freeze

    BADGE_VARIANTS = {
      DRAFT => :secondary,
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
