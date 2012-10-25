class CreateAdminProposalsAnswers < ActiveRecord::Migration
  def change
    create_table :admin_proposals_answers do |t|
      t.string :answer

      t.timestamps
    end
  end
end
