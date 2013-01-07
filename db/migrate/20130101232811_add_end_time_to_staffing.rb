class AddEndTimeToStaffing < ActiveRecord::Migration
  def change
    add_column :admin_staffings, :end_time, :datetime
  end
end
