class AddMissingForeignKeyIndexesToJoinTables < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_permissions_roles, :permission_id, if_not_exists: true
    add_index :children_techies, :child_id, if_not_exists: true
  end
end
