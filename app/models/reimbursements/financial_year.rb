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
  # A financial year ("Fringe 2026") — orthogonal to cost centre: each year has
  # its own budgets, expenses and actuals. One year is active at a time; past
  # years stay viewable through the budget screens' year selector.
  #
  # A year is built as a DRAFT: created, its budgets imported and checked, and
  # only then made active with #activate!. Until that moment the outgoing year
  # keeps the flag, so the submitter budget picker (which always follows
  # .current) never changes under an operator who is still setting next year up.
  class FinancialYear < ApplicationRecord
    include RecordId
    has_many :budgets, class_name: "Reimbursements::Budget", dependent: :restrict_with_error
    has_many :expenses, class_name: "Reimbursements::Expense", dependent: :restrict_with_error
    has_many :eusa_actuals, class_name: "Reimbursements::EusaActual", dependent: :restrict_with_error

    # The +key+ is the URL slug (`?year=fringe-2027`, `find_by(key:)`), so it
    # must be URL-safe. Derived from the label by default, exactly as
    # CostCentre#key is derived from its name.
    before_validation :derive_key_from_label

    validates :label, presence: true, uniqueness: true
    validates :key, presence: true, uniqueness: true
    validates :key, format: { with: /\A[a-z0-9-]+\z/,
                              message: "may only contain lowercase letters, numbers and hyphens" },
                    allow_blank: true
    validate :only_one_active

    scope :active, -> { where(active: true) }
    # Newest first for the year list and the selector. A year with no start date
    # sorts to the top: it is the one still being set up, so it is the one the
    # operator has come to find.
    scope :recent_first, -> { order(Arel.sql("starts_on IS NULL DESC"), starts_on: :desc, id: :desc) }

    def self.current
      active.first
    end

    def to_param = key

    # Make this the year submitters file against, moving the flag off whichever
    # year holds it. The incumbent has to be stood down FIRST — #only_one_active
    # would reject this record while another year still holds the flag — which
    # is precisely why both statements share one transaction: if this record
    # then fails to save, the incumbent gets its flag back rather than leaving
    # the portal with no active year at all.
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
