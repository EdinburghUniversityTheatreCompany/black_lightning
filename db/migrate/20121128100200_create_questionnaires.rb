class CreateQuestionnaires < ActiveRecord::Migration
  def change
    create_table :admin_questionnaires_questionnaires do |t|
      t.integer :show_id

      t.timestamps
    end

    create_table :admin_questionnaires_questionnaire_templates do |t|
      t.integer :name

      t.timestamps
    end
  end
end
