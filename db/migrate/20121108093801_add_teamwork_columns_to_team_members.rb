class AddTeamworkColumnsToTeamMembers < ActiveRecord::Migration
  def change
    rename_column :team_members, :proposal_id, :teamwork_id    
    add_column :team_members, :teamwork_type, :string
    
    TeamMember.connection.execute("update team_members set teamwork_type='Admin::Proposals::Proposal'")
  end
end
