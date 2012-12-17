class AddOrderToTeamMembers < ActiveRecord::Migration
  def change
    add_column :team_members, :display_order, :integer
  end
end
