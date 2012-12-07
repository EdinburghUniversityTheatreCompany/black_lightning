class AddNameToAdminQuestionnairesQuestionnaire < ActiveRecord::Migration
  def change
    add_column :admin_questionnaires_questionnaires, :name, :string
  end
end
