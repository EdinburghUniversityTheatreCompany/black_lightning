class CreateAdminProposalsAnswers < ActiveRecord::Migration
  def change
    create_table :admin_proposals_answers do |t|
      t.text :answer

      t.timestamps
    end
  end
end
