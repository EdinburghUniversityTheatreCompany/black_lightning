class AddScheduledJobIdBackToStaffings < ActiveRecord::Migration[8.0]
  def change
    add_column :admin_staffings, :scheduled_job_id, :string
  end
end
