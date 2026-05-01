class RemoveReminderJobIdFromStaffings < ActiveRecord::Migration[8.1]
  def change
    remove_index :admin_staffings, :reminder_job_id
    remove_column :admin_staffings, :reminder_job_id, :integer
  end
end
