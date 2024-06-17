class AddUniqueIndexToTeamMembers < ActiveRecord::Migration[7.0]
  def change
    add_index :team_members, [:teamwork_id, :teamwork_type, :user_id], unique: true, name: 'index_team_members_on_teamwork_and_user'
  end
end
