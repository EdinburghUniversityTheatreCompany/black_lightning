class CreateOpportunityRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :opportunity_roles do |t|
      t.references :opportunity, null: false, foreign_key: true, type: :integer
      t.string :position, null: false
      t.integer :category, null: false, default: 0
      t.string :note
      t.integer :ordering

      t.timestamps
    end
  end
end
