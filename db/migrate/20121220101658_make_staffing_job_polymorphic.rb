class MakeStaffingJobPolymorphic < ActiveRecord::Migration
  def change
    rename_column :admin_staffing_jobs, :staffing_id,    :staffable_id
    add_column    :admin_staffing_jobs, :staffable_type, :string
  end
end
