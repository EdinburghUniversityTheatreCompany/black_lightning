class AddDisplayOrderToTeamMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :team_members, :display_order, :integer
  end
end
