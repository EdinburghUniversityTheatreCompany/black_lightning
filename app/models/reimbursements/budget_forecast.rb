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
#  area_id            :bigint
#  budget_id          :bigint
#  budget_update_id   :bigint
#
# Indexes
#
#  index_reimbursements_budget_forecasts_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_budget_forecasts_on_area_id             (area_id)
#  index_reimbursements_budget_forecasts_on_budget_id           (budget_id)
#  index_reimbursements_budget_forecasts_on_budget_update_id    (budget_update_id)
#
# Foreign Keys
#
#  fk_rails_...  (area_id => reimbursements_areas.id)
#  fk_rails_...  (budget_id => reimbursements_budgets.id)
#  fk_rails_...  (budget_update_id => reimbursements_budget_updates.id)
#
module Reimbursements
  ##
  # A versioned projected-expenditure update for a budget OR an area. The
  # latest row (date desc) is the owner's current_forecast.
  class BudgetForecast < ApplicationRecord
    include RecordId
    belongs_to :budget, class_name: "Reimbursements::Budget", optional: true, inverse_of: :forecasts
    # An area-level forecast revises the area's agreed total rather than one
    # budget's allocation. Exactly one of budget/area is set — see
    # belongs_to_exactly_one_owner below.
    belongs_to :area, class_name: "Reimbursements::Area", optional: true, inverse_of: :forecasts
    # The batched revision that logged this forecast, when it came from a
    # multi-budget "budget update" rather than a standalone per-budget entry.
    belongs_to :budget_update, class_name: "Reimbursements::BudgetUpdate",
                               optional: true, inverse_of: :forecasts

    validates :amount, presence: true
    validate :belongs_to_exactly_one_owner

    # The PORO exposed the linked budget's record id string (compared against
    # budget.record_id in the Store and views); AR's own reader would return
    # the integer FK.
    def budget_id = self[:budget_id]&.to_s

    # Display label: "<budget or area> - YYYY-MM-DD".
    def name
      [ (budget || area)&.name, date&.strftime("%Y-%m-%d") ].compact.join(" - ")
    end

    private

    # Belt and braces on top of the CHECK constraint added in
    # AllowAreaBudgetForecasts: this gives the operator a readable message,
    # the constraint catches a write that bypasses AR validations.
    def belongs_to_exactly_one_owner
      return if budget_id.present? ^ area_id.present?

      errors.add(:base, "must belong to either a budget or an area, not both and not neither")
    end
  end
end
