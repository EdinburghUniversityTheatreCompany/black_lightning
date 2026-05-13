class AddTimeIndexesToAdminStaffings < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_staffings, :start_time, if_not_exists: true
    add_index :admin_staffings, :end_time, if_not_exists: true
  end
end
