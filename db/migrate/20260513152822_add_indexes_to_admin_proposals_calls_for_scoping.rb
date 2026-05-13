class AddIndexesToAdminProposalsCallsForScoping < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_proposals_calls, :archived, if_not_exists: true
    add_index :admin_proposals_calls, :submission_deadline, if_not_exists: true
    add_index :admin_proposals_calls, :editing_deadline, if_not_exists: true
  end
end
