class AddIndexToAdminProposalsProposalsStatus < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_proposals_proposals, :status, if_not_exists: true
  end
end
