class AddDebtAmountsToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :maintenance_debt_amount, :integer
    add_column :events, :staffing_debt_amount, :integer
  end
end
