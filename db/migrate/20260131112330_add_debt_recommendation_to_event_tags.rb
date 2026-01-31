class AddDebtRecommendationToEventTags < ActiveRecord::Migration[8.1]
  def change
    add_column :event_tags, :recommended_maintenance_debts, :integer
    add_column :event_tags, :recommended_staffing_debts, :integer
  end
end
