class AddLateToProposals < ActiveRecord::Migration
  def change
    add_column :admin_proposals_proposals, :late, :boolean
  end
end
