class AddCallIdToProposals < ActiveRecord::Migration
  def change
    add_column :admin_proposals_proposals, :call_id, :integer
  end
end
