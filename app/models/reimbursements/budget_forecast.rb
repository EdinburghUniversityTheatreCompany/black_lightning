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
    # An area forecast revises the area's agreed total. Exactly one of
    # budget/area is set.
    belongs_to :area, class_name: "Reimbursements::Area", optional: true, inverse_of: :forecasts
    # Set when the forecast came from a multi-budget update.
    belongs_to :budget_update, class_name: "Reimbursements::BudgetUpdate",
                               optional: true, inverse_of: :forecasts

    validates :amount, presence: true
    validate :belongs_to_exactly_one_owner

    # A String, to match Budget#record_id keys (e.g. the budget_updates index's
    # @budgets_by_id).
    def budget_id = self[:budget_id]&.to_s

    private

    # Belt and braces over the CHECK constraint, for a readable message.
    def belongs_to_exactly_one_owner
      return if budget_id.present? ^ area_id.present?

      errors.add(:base, "must belong to either a budget or an area, not both and not neither")
    end
  end
end
