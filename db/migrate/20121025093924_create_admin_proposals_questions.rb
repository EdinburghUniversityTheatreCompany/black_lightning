class CreateAdminProposalsQuestions < ActiveRecord::Migration
  def change
    create_table :admin_proposals_questions do |t|
      t.string :question_text

      t.timestamps
    end
  end
end
