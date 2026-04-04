class AddCalendarSequenceToStaffingJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_staffing_jobs, :calendar_sequence, :integer, default: 0, null: false
  end
end
