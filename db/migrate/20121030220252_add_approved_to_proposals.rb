class AddApprovedToProposals < ActiveRecord::Migration
  def change
    add_column :admin_proposals_proposals, :approved, :boolean
  end
end
