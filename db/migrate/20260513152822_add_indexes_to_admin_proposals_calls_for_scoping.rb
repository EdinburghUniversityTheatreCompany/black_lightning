class AddIndexesToAdminProposalsCallsForScoping < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_proposals_calls, :archived
    add_index :admin_proposals_calls, :submission_deadline
    add_index :admin_proposals_calls, :editing_deadline
  end
end
