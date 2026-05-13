class AddMissingForeignKeyIndexesToOpportunities < ActiveRecord::Migration[8.1]
  def change
    add_index :opportunities, :approver_id
    add_index :opportunities, :creator_id
  end
end
