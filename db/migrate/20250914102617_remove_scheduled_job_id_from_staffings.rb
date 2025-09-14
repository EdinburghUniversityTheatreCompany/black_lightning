class RemoveScheduledJobIdFromStaffings < ActiveRecord::Migration[8.0]
  def change
    remove_column :admin_staffings, :scheduled_job_id, :string
  end
end
