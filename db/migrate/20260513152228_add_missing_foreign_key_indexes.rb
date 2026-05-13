class AddMissingForeignKeyIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_feedbacks, :show_id, if_not_exists: true
    add_index :admin_permissions_roles, :permission_id, if_not_exists: true
    add_index :admin_questionnaires_questionnaires, :event_id, if_not_exists: true
    add_index :attachments, :editable_block_id, if_not_exists: true
    add_index :children_techies, :child_id, if_not_exists: true
    add_index :mass_mails, :sender_id, if_not_exists: true
    add_index :opportunities, :approver_id, if_not_exists: true
    add_index :opportunities, :creator_id, if_not_exists: true
    add_index :reviews, :event_id, if_not_exists: true
    add_index :admin_staffing_debts, :admin_staffing_job_id, if_not_exists: true
  end
end
