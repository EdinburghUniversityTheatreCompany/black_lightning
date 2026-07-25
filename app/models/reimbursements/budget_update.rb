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
  # e.g. the outcome of a production budget meeting. It groups the
  # BudgetForecast rows it created (one per changed budget) under one shared
  # effective date, note and author.
  #
  # The link is backward-compatible: a forecast's budget_update_id is nullable,
  # so standalone per-budget forecasts stay unlinked and "latest forecast wins"
  # in Budget#current_forecast is untouched — a batched forecast is still just a
  # BudgetForecast row, editable through the existing per-budget log.
  class BudgetUpdate < ApplicationRecord
    include RecordId

    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true
    belongs_to :created_by, class_name: "User", optional: true
    has_many :forecasts, class_name: "Reimbursements::BudgetForecast",
                         dependent: :nullify, inverse_of: :budget_update

    validates :effective_date, presence: true
  end
end
