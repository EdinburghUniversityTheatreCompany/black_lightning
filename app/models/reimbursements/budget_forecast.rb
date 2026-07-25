# == Schema Information
#
# Table name: reimbursements_budget_forecasts
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  amount             :decimal(12, 2)
#  date               :date
#  reason             :text(65535)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  airtable_record_id :string(255)
#  budget_id          :bigint           not null
#  budget_update_id   :bigint
#
# Indexes
#
#  index_reimbursements_budget_forecasts_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_budget_forecasts_on_budget_id           (budget_id)
#  index_reimbursements_budget_forecasts_on_budget_update_id    (budget_update_id)
#
# Foreign Keys
#
#  fk_rails_...  (budget_id => reimbursements_budgets.id)
#  fk_rails_...  (budget_update_id => reimbursements_budget_updates.id)
#
module Reimbursements
  ##
  # A versioned projected-expenditure update for a budget. The latest row
  # (date desc) is the budget's current_forecast.
  class BudgetForecast < ApplicationRecord
    include RecordId
    belongs_to :budget, class_name: "Reimbursements::Budget", inverse_of: :forecasts
    # The batched revision that logged this forecast, when it came from a
    # multi-budget "budget update" rather than a standalone per-budget entry.
    belongs_to :budget_update, class_name: "Reimbursements::BudgetUpdate",
                               optional: true, inverse_of: :forecasts

    validates :amount, presence: true

    # The PORO exposed the linked budget's record id string (compared against
    # budget.record_id in the Store and views); AR's own reader would return
    # the integer FK.
    def budget_id = self[:budget_id]&.to_s

    # Display label: "<budget> - YYYY-MM-DD".
    def name
      [ budget&.name, date&.strftime("%Y-%m-%d") ].compact.join(" - ")
    end
  end
end
