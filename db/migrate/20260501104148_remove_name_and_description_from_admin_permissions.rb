class RemoveNameAndDescriptionFromAdminPermissions < ActiveRecord::Migration[8.1]
  def change
    remove_column :admin_permissions, :name, :string
    remove_column :admin_permissions, :description, :string
  end
end
