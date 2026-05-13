class AddTimeIndexesToAdminStaffings < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_staffings, :start_time
    add_index :admin_staffings, :end_time
  end
end
