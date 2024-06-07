class AddUniqueIndexToTeamMembers < ActiveRecord::Migration[7.0]
  def change
    add_index :team_members, [:teamwork_id, :user_id], unique: true
  end
end
