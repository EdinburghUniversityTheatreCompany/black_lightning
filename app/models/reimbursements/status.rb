module Reimbursements
  ##
  # Expense status labels, mirroring the Airtable single-select exactly.
  # The portal writes Draft and Pending (submitting a draft promotes it);
  # bedlam-bacs owns the rest of the state machine and ignores Drafts.
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
