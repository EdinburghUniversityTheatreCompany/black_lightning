class AddConvertedFromStaffingDebtToMaintenanceDebts < ActiveRecord::Migration[7.0]
  def change
    add_column :admin_maintenance_debts, :converted_from_staffing_debt, :boolean, default: false, null: false
  end
end
