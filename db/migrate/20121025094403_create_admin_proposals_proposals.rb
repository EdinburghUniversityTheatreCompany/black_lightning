class CreateAdminProposalsProposals < ActiveRecord::Migration
  def change
    create_table :admin_proposals_proposals do |t|
      t.string :show_title
      t.integer :cast_male
      t.integer :cast_female
      t.time :running_time
      t.string :publicity_text
      t.string :proposal_text
      t.decimal :budget_royalties
      t.decimal :budget_publiciy
      t.decimal :budget_tech
      t.decimal :budget_set
      t.decimal :budget_costume
      t.decimal :budget_props
      t.decimal :budget_admin
      t.decimal :budget_contingency
      t.decimal :budget_eutc
      t.decimal :budget_other_sources

      t.timestamps
    end
  end
end
