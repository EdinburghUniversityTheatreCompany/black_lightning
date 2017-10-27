class AddStateToAdminMaintenanceDebt < ActiveRecord::Migration
  def change
    add_column :admin_maintenance_debts, :state, :integer, default: 0
  end
end
