class CreateAdminProposalsProposals < ActiveRecord::Migration
  def change
    create_table :admin_proposals_proposals do |t|
      t.integer :call_id
      t.string :show_title
      t.text :publicity_text
      t.text :proposal_text

      t.timestamps
    end
  end
end
