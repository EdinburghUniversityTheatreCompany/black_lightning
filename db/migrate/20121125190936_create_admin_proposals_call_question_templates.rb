class CreateAdminProposalsCallQuestionTemplates < ActiveRecord::Migration
  def change
    create_table :admin_proposals_call_question_templates do |t|
      t.string :name
      t.timestamps
    end

    create_table :call_question_templates_questions, :id => false do |t|
      t.integer :call_question_template_id
      t.integer :question_id
    end
  end
end
