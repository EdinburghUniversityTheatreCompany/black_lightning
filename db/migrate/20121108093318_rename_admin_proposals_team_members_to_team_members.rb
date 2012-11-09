class RenameAdminProposalsTeamMembersToTeamMembers < ActiveRecord::Migration
  def change
    rename_table :admin_proposals_team_members, :team_members
  end
end
