class CreateProposalCallQuestionJoinTable < ActiveRecord::Migration
  def up
    create_table :admin_proposals_calls_questions, :id => false do |t|
      t.integer :proposals_call_id
      t.integer :proposals_question_id
    end
  end

  def down
    drop_table :admin_proposals_calls_questions
  end
end
