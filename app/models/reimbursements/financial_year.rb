# == Schema Information
#
# Table name: reimbursements_financial_years
# Database name: primary
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(FALSE), not null
#  ends_on    :date
#  key        :string(255)      not null
#  label      :string(255)      not null
#  starts_on  :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_reimbursements_financial_years_on_active  (active)
#  index_reimbursements_financial_years_on_key     (key) UNIQUE
#  index_reimbursements_financial_years_on_label   (label) UNIQUE
#
module Reimbursements
  ##
  # A financial year ("Fringe 2026"), orthogonal to cost centre. One year is active at a time.
  #
  # A year is built as a DRAFT and only then made active with #activate!, so the submitter
  # budget picker (which follows .current) never changes under an operator still setting up.
  class FinancialYear < ApplicationRecord
    include RecordId
    has_many :budgets, class_name: "Reimbursements::Budget", dependent: :restrict_with_error
    has_many :expenses, class_name: "Reimbursements::Expense", dependent: :restrict_with_error
    has_many :eusa_actuals, class_name: "Reimbursements::EusaActual", dependent: :restrict_with_error

    # +key+ is the URL slug (`?year=fringe-2027`), so it must be URL-safe.
    before_validation :derive_key_from_label

    validates :label, presence: true, uniqueness: true
    validates :key, presence: true, uniqueness: true
    validates :key, format: { with: /\A[a-z0-9-]+\z/,
                              message: "may only contain lowercase letters, numbers and hyphens" },
                    allow_blank: true
    validate :only_one_active

    scope :active, -> { where(active: true) }
    # A year with no start date sorts first: it is the one still being set up.
    scope :recent_first, -> { order(Arel.sql("starts_on IS NULL DESC"), starts_on: :desc, id: :desc) }

    def self.current
      active.first
    end

    def to_param = key

    # :active, :past or :draft. A non-active year is not automatically a draft: it is past once
    # its start date has arrived, and one with no dates can only be a draft.
    def status
      return :active if active?
      return :past if starts_on.present? && starts_on <= Date.current

      :draft
    end

    # The incumbent is stood down first (#only_one_active), inside one transaction, so a failed
    # save never leaves the portal with no active year.
    def activate!
      return self if active?

      self.class.transaction do
        self.class.where.not(id: id).active.update_all(active: false, updated_at: Time.current)
        update!(active: true)
      end
      self
    end

    private

    def derive_key_from_label
      self.key = label.to_s.parameterize if key.blank? && label.present?
    end

    def only_one_active
      return unless active?
      return unless self.class.active.where.not(id: id).exists?

      errors.add(:active, "is already set on another financial year.")
    end
  end
end
