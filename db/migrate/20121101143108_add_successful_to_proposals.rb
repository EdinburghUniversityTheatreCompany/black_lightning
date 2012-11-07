class AddSuccessfulToProposals < ActiveRecord::Migration
  def change
    add_column :admin_proposals_proposals, :successful, :boolean
  end
end
