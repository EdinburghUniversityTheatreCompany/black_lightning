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
    # The LABEL is unique per centre too, and that is correctness: BudgetFinder
    # matches a hand-named budget line against it, so two codes sharing a label
    # have one uncoded line answering to both — and once a line exists for one,
    # the other can never be opened at all. Case-insensitive for the reason
    # above.
    validates :label, uniqueness: { scope: :cost_centre_id, case_sensitive: false }

    scope :for_cost_centre, ->(cost_centre) { where(cost_centre: cost_centre).order(:code) }

    # The rows this centre's list is answerable for: budget lines and imported
    # EUSA ledger rows, each carrying a nominal code as a STRING rather than a
    # link to this table, so the list is the only thing that gives one a label.
    #
    # Each scope takes the centre's own rows plus the ones with NO centre: an
    # unplaced row is lenient-scoped into EVERY centre's screens
    # (DatabaseStore#in_cost_centre), the same rule NominalCodeSeed folds an
    # unplaced code into the default centre by.
    def self.budgets_for(cost_centre)
      Budget.where(cost_centre_id: [ cost_centre&.id, nil ])
    end

    def self.actuals_for(cost_centre)
      EusaActual.where(cost_centre_id: [ cost_centre&.id, nil ])
    end

    # How many rows of each kind carry each of +codes+, as
    # { "432320" => { budgets: 2, actuals: 9 } }, keyed DOWNCASED because both
    # columns are utf8mb4_unicode_ci and a row in another case means the same
    # account. One query per kind rather than per row, off the same pair of
    # scopes #in_use? reads: the screen predicts what would happen to each code.
    #
    # Same rows, but NOT the same matching, and it can disagree one way.
    # #in_use? asks SQL under utf8mb4_unicode_ci, which is PAD SPACE and folds
    # accents; this keys in Ruby on #downcase, which is neither. So a budget
    # storing "432320 " counts for #in_use? and lands under a key the row fails
    # to find: the button predicts Delete over a code #destroy correctly
    # retires. Safe direction, the controller re-decides, and never the reverse
    # — anything this counts, SQL matches too.
    def self.usage_counts(cost_centre, codes)
      budgets = tally_codes(budgets_for(cost_centre), codes)
      actuals = tally_codes(actuals_for(cost_centre), codes)
      (budgets.keys | actuals.keys).index_with do |code|
        { budgets: budgets.fetch(code, 0), actuals: actuals.fetch(code, 0) }
      end
    end

    def self.tally_codes(scope, codes)
      scope.where(nominal_code: codes).group(:nominal_code).count
           .transform_keys { |code| code.to_s.downcase }
    end
    private_class_method :tally_codes

    # Whether any historical row carries this code — what decides retire versus
    # delete, read in #destroy rather than from the button that was clicked. A
    # code a settled claim or a reconciled ledger row was booked against must
    # stay readable, so anything at all counts.
    def in_use?
      self.class.budgets_for(cost_centre).exists?(nominal_code: code) ||
        self.class.actuals_for(cost_centre).exists?(nominal_code: code)
    end
  end
end
