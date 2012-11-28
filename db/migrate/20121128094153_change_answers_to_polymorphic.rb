class ChangeAnswersToPolymorphic < ActiveRecord::Migration
  def change
    rename_table :admin_proposals_answers, :admin_answers

    rename_column :admin_answers, :proposal_id, :answerable_id

    add_column :admin_answers, :answerable_type, :string
  end
end
