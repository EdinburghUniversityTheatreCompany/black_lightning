class AddMissingForeignKeyIndexesToOpportunities < ActiveRecord::Migration[8.1]
  def change
    add_index :opportunities, :approver_id, if_not_exists: true
    add_index :opportunities, :creator_id, if_not_exists: true
  end
end
