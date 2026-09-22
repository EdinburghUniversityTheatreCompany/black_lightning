class AddProposalWithdrawnFlag < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_proposals_proposals, :withdrawn, :boolean, null: false, default: false
  end
end
