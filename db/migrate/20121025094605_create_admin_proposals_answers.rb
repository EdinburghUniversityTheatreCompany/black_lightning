class CreateAdminProposalsAnswers < ActiveRecord::Migration
  def change
    create_table :admin_proposals_answers do |t|
      t.integer :question_id
      t.integer :proposal_id

      t.text :answer

      t.timestamps
    end
  end
end
