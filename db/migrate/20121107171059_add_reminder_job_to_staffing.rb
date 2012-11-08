class AddReminderJobToStaffing < ActiveRecord::Migration
  def change
  	add_column :admin_staffings, :reminder_job_id, :integer
  end
end
