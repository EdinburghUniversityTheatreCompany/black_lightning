class AddMissingForeignKeyIndexesToAssociations < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_feedbacks, :show_id, if_not_exists: true
    add_index :admin_questionnaires_questionnaires, :event_id, if_not_exists: true
    add_index :reviews, :event_id, if_not_exists: true
    add_index :mass_mails, :sender_id, if_not_exists: true
  end
end
