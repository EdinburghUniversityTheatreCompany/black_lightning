# == Schema Information
#
# Table name: reimbursements_nominal_codes
# Database name: primary
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(TRUE), not null
#  code           :string(255)      not null
#  label          :string(255)      not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  cost_centre_id :bigint           not null
#
# Indexes
#
#  index_reimbursements_nominal_codes_on_centre_and_code  (cost_centre_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#
module Reimbursements
  ##
  # One line of a cost centre's chart of accounts. Owned by that centre alone
  # — a global list would let Fringe's admin retire a code Bedlam books
  # against. code is a STRING and stays one: codes are zero-padded (041000),
  # the same coercion Exports::Base#add_sheet guards against for xlsx cells.
  class NominalCode < ApplicationRecord
    include RecordId

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre"

    validates :code, :label, presence: true
    # case_sensitive: false because the column is utf8mb4_unicode_ci — the DB
    # index already folds case and accents, so a case-sensitive validation
    # would disagree with it and let a duplicate through to a RecordNotUnique.
    validates :code, uniqueness: { scope: :cost_centre_id, case_sensitive: false }

    scope :for_cost_centre, ->(cost_centre) { where(cost_centre: cost_centre).order(:code) }

    # The budget lines this centre's list is answerable for: its own, plus the
    # ones with NO centre of their own. An unplaced budget is lenient-scoped
    # into EVERY centre's screens (DatabaseStore#in_cost_centre), so this
    # centre's list is what labels its code there — the same rule
    # NominalCodeSeed folds an unplaced code into the default centre by.
    def self.budgets_for(cost_centre)
      Budget.where(cost_centre_id: [ cost_centre&.id, nil ])
    end

    # How many of those budgets carry each of +codes+, keyed by the code
    # DOWNCASED: the column is utf8mb4_unicode_ci, so a budget may carry the
    # same code in another case and still be the same account.
    def self.budget_counts(cost_centre, codes)
      budgets_for(cost_centre).where(nominal_code: codes)
                              .group(:nominal_code).count
                              .transform_keys { |code| code.to_s.downcase }
    end

    # Whether a budget line already carries this code. What decides retire
    # versus delete — read in #destroy, not from the button that was clicked.
    def in_use?
      self.class.budgets_for(cost_centre).exists?(nominal_code: code)
    end
  end
end
