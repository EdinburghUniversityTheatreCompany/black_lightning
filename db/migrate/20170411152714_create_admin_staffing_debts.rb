class CreateAdminStaffingDebts < ActiveRecord::Migration
  def change
    create_table :admin_staffing_debts do |t|
      t.integer :user_id
      t.integer :show_id
      t.date :due_by
      t.integer :admin_staffing_job_id

      t.timestamps null: false
    end
  end
end
