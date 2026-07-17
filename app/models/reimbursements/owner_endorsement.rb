# == Schema Information
#
# Table name: reimbursements_owner_endorsements
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  endorsed_at           :datetime         not null
#  note                  :string(255)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  budget_record_id      :string(255)      not null
#  endorsed_by_person_id :string(255)
#  expense_record_id     :string(255)      not null
#  overridden_by_id      :integer
#
# Indexes
#
#  index_reimbursements_owner_endorsements_on_expense_record_id  (expense_record_id) UNIQUE
#  index_reimbursements_owner_endorsements_on_overridden_by_id   (overridden_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (overridden_by_id => users.id)
#
module Reimbursements
  ##
  # A budget owner's blocking sign-off that an expense charged to their budget
  # is legitimate. The finance team can't approve a gated expense until one
  # exists (any one owner suffices) — or until finance overrides the gate
  # (recorded here as +overridden_by+ with no endorsing person). A submitter who
  # owns the budget is auto-bypassed by the gate and needs no row here.
  #
  # Lives in MySQL (Airtable's schema isn't ours to change) keyed by the
  # Airtable expense/budget record ids; survives the planned cutover.
  class OwnerEndorsement < ApplicationRecord
    # The finance user who overrode the gate (nil for a genuine owner sign-off).
    belongs_to :overridden_by, class_name: "User", optional: true

    validates :expense_record_id, :budget_record_id, :endorsed_at, presence: true
    # One satisfaction per expense — a friendly error ahead of the unique index.
    validates :expense_record_id, uniqueness: true
    validate :either_an_owner_or_an_override

    # One satisfaction per expense (enforced by a unique index too).
    scope :for_expense, ->(expense_record_id) { where(expense_record_id: expense_record_id) }

    def owner_endorsement?
      endorsed_by_person_id.present?
    end

    def finance_override?
      overridden_by_id.present?
    end

    private

    # Exactly one satisfaction path: an owner endorsed, or finance overrode.
    def either_an_owner_or_an_override
      if endorsed_by_person_id.blank? && overridden_by_id.blank?
        errors.add(:base, "must record an endorsing owner or a finance override.")
      elsif endorsed_by_person_id.present? && overridden_by_id.present?
        errors.add(:base, "can't be both an owner endorsement and a finance override.")
      end
    end
  end
end
