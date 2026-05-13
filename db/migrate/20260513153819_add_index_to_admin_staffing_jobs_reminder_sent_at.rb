class AddIndexToAdminStaffingJobsReminderSentAt < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_staffing_jobs, :reminder_sent_at
  end
end
