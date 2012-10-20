class CreateAdminStaffingJobs < ActiveRecord::Migration
  def change
    create_table :admin_staffing_jobs do |t|
      t.string     :name
      t.integer    :staffing_id
      t.integer    :user_id
      t.timestamps
    end
  end
end
