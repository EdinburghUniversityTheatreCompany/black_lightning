class AddQuestionnairesToEvent < ActiveRecord::Migration[6.0]
  def change
    rename_column :admin_questionnaires_questionnaires, :show_id, :event_id
    change_column :admin_questionnaires_questionnaires, :event_id, :int, foreign_key: true 
  end
end
