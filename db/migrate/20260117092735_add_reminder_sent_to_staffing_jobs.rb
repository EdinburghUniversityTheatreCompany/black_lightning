class AddReminderSentToStaffingJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_staffing_jobs, :reminder_sent_at, :datetime
  end
end
