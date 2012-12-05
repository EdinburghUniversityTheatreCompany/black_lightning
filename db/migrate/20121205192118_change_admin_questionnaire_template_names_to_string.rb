class ChangeAdminQuestionnaireTemplateNamesToString < ActiveRecord::Migration
  def change
    change_column :admin_questionnaires_questionnaire_templates, :name, :string
  end
end
