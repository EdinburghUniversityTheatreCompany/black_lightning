class CreateAdminProposalsCalls < ActiveRecord::Migration
  def change
    create_table :admin_proposals_calls do |t|
      t.datetime :deadline
      t.string :name
      t.boolean :open

      t.timestamps
    end
  end
end
