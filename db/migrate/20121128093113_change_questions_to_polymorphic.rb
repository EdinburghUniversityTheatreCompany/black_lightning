class ChangeQuestionsToPolymorphic < ActiveRecord::Migration
  def change
    drop_table :calls_questions
    drop_table :call_question_templates_questions

    rename_table :admin_proposals_questions, :admin_questions

    add_column :admin_questions, :questionable_id, :integer
    add_column :admin_questions, :questionable_type, :string
  end
end
