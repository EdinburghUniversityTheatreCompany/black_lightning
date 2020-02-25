class AddCountsTowardsDebtToStaffing < ActiveRecord::Migration
  def change
    add_column :admin_staffings, :counts_towards_debt, :boolean
  end
end
