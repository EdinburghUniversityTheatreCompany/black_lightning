# == Schema Information
#
# Table name: reimbursements_budget_updates
# Database name: primary
#
#  id                :bigint           not null, primary key
#  effective_date    :date             not null
#  note              :text(65535)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  created_by_id     :integer
#  financial_year_id :bigint
#
# Indexes
#
#  index_reimbursements_budget_updates_on_created_by_id      (created_by_id)
#  index_reimbursements_budget_updates_on_financial_year_id  (financial_year_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (financial_year_id => reimbursements_financial_years.id)
#
module Reimbursements
  ##
  # A single annotated revision covering several budgets' forecasts at once —
  # e.g. a budget meeting's outcome, under a shared date, note and author.
  # Standalone forecasts have no update.
  class BudgetUpdate < ApplicationRecord
    include RecordId

    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    belongs_to :created_by, class_name: "User", optional: true
    has_many :forecasts, class_name: "Reimbursements::BudgetForecast",
                         dependent: :destroy, inverse_of: :budget_update

    validates :effective_date, presence: true
  end
end
