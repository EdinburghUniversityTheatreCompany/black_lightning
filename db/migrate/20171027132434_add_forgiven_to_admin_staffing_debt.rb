class AddForgivenToAdminStaffingDebt < ActiveRecord::Migration
  def change
    add_column :admin_staffing_debts, :forgiven, :boolean, default: false
  end
end
