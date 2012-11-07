class CreateProposalCallQuestionJoinTable < ActiveRecord::Migration
  def up
    create_table :calls_questions, :id => false do |t|
      t.integer :call_id
      t.integer :question_id
    end
  end

  def down
    drop_table :calls_questions
  end
end
