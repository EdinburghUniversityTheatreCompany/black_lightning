class RemoveDisplayOrderFromTeamMember < ActiveRecord::Migration
  def change
    remove_column :team_members, :display_order, :integer
  end
end
