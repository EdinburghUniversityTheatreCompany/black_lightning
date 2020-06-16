class AddProposalToEvent < ActiveRecord::Migration[6.0]
  def change
    add_reference :events, :admin_proposals_proposal, null: false, type: :integer
    add_foreign_key :events, :admin_proposals_proposals
  end
end
