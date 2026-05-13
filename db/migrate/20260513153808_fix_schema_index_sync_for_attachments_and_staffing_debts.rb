class FixSchemaIndexSyncForAttachmentsAndStaffingDebts < ActiveRecord::Migration[8.1]
  def change
    add_index :attachments, :editable_block_id, if_not_exists: true
    add_index :admin_staffing_debts, :admin_staffing_job_id, if_not_exists: true
  end
end
