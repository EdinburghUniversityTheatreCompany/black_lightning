class AddStaffingDebtStartToEvents < ActiveRecord::Migration
  def change
    add_column :events, :staffing_debt_start, :date
  end
end
