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
  # One line of a cost centre's chart of accounts, owned by that centre alone.
  # +code+ is a string because codes are zero-padded (041000).
  class NominalCode < ApplicationRecord
    include RecordId

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre"

    validates :code, :label, presence: true
    # case_sensitive: false because the column is utf8mb4_unicode_ci: a
    # case-sensitive check would let a duplicate through to RecordNotUnique.
    validates :code, uniqueness: { scope: :cost_centre_id, case_sensitive: false }
    # A unique label is correctness: BudgetFinder matches a hand-named line by
    # label, so two codes sharing one would both claim the same line.
    validates :label, uniqueness: { scope: :cost_centre_id, case_sensitive: false }

    scope :for_cost_centre, ->(cost_centre) { where(cost_centre: cost_centre).order(:code) }

    # Active [code, label] pairs to suggest: the centre's own, or with none
    # every centre's deduped by code (the first label wins; it is only a hint).
    def self.suggestions_for(cost_centre)
      scope = cost_centre ? where(cost_centre_id: [ cost_centre.id, nil ]) : all
      scope.where(active: true).order(:code, :id)
           .pluck(:code, :label)
           .uniq { |code, _| code.to_s.downcase }
    end

    # code => label for printing stored codes, keyed downcased as the
    # utf8mb4_unicode_ci columns compare. Retired codes still label old rows.
    def self.labels_for(cost_centre)
      scope = cost_centre ? where(cost_centre_id: [ cost_centre.id, nil ]) : all
      scope.order(:code, :id).pluck(:code, :label)
           .to_h { |code, label| [ code.to_s.downcase, label ] }
    end

    # The rows carrying a code as a string: this centre's plus the unplaced
    # (NULL centre) ones, which are lenient-scoped into every centre.
    def self.budgets_for(cost_centre)
      Budget.where(cost_centre_id: [ cost_centre&.id, nil ])
    end

    def self.actuals_for(cost_centre)
      EusaActual.where(cost_centre_id: [ cost_centre&.id, nil ])
    end

    # { "432320" => { budgets: 2, actuals: 9 } }, keyed downcased, so the screen
    # can predict what #destroy will do. It can disagree with #in_use? one way:
    # SQL under utf8mb4_unicode_ci is PAD SPACE and folds accents, #downcase is
    # neither, so a "432320 " budget shows Delete for a code #destroy retires.
    # That is the safe direction; never the reverse.
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

    # Any historical row carrying the code means retire, not delete.
    def in_use?
      self.class.budgets_for(cost_centre).exists?(nominal_code: code) ||
        self.class.actuals_for(cost_centre).exists?(nominal_code: code)
    end
  end
end
