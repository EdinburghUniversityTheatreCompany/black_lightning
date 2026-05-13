class AddDisplayOrderIndexToTeamMembers < ActiveRecord::Migration[8.1]
  def change
    add_index :team_members, :display_order
  end
end
