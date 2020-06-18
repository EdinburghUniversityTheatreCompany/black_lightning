class AddProposalToEvent < ActiveRecord::Migration[6.0]
  def change
    add_belongs_to :events, :proposal, null: true, type: :integer, foreign_key: { to_table: :admin_proposals_proposals }
  end
end
