class RenameDateToStartTimeInStaffing < ActiveRecord::Migration
  def change
    rename_column :admin_staffings, :date, :start_time
  end
end
