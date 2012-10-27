class CreateAdminProposalsTeamMembers < ActiveRecord::Migration
  def change
    create_table :admin_proposals_team_members do |t|
      t.string :position
      t.integer :user_id
      t.integer :proposal_id

      t.timestamps
    end
  end
end
