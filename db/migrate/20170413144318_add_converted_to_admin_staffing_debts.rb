class AddConvertedToAdminStaffingDebts < ActiveRecord::Migration
  def change
    add_column :admin_staffing_debts, :converted, :boolean
  end
end
