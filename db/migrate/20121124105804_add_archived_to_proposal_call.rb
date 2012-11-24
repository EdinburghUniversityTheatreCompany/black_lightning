class AddArchivedToProposalCall < ActiveRecord::Migration
  def change
    add_column :admin_proposals_calls, :archived, :boolean
  end
end
