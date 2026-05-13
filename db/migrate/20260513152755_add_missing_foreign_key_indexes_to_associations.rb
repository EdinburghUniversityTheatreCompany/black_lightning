class AddMissingForeignKeyIndexesToAssociations < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_feedbacks, :show_id
    add_index :admin_questionnaires_questionnaires, :event_id
    add_index :reviews, :event_id
    add_index :mass_mails, :sender_id
  end
end
