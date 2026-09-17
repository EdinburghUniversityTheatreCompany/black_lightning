class RenameRolesToGroups < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      rename_table :roles, :groups
      rename_table :users_roles, :groups_users
      rename_table :roles_parents, :groups_parents
      rename_table :admin_permissions_roles, :admin_permissions_groups

      change_table :groups_users do |t|
        t.rename :role_id, :group_id
      end

      change_table :groups_parents do |t|
        t.rename :role_id, :group_id
      end

      change_table :admin_permissions_groups do |t|
        t.rename :role_id, :group_id
      end
    end
  end
end
