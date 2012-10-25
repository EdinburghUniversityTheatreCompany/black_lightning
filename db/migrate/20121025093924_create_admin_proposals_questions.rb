class CreateAdminProposalsQuestions < ActiveRecord::Migration
  def change
    create_table :admin_proposals_questions do |t|
      t.text :question_text

      t.timestamps
    end
  end
end
