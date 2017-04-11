class AddMaintenanceDebtStartToShows < ActiveRecord::Migration
  def change
    add_column :events, :maintenance_debt_start, :date
  end
end
