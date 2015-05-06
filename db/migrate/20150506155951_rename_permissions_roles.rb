class RenamePermissionsRoles < ActiveRecord::Migration
  def change
    rename_table :permissions_roles, :admin_permissions_roles
  end
end
