class AddIndexToUsersRolesRoleId < ActiveRecord::Migration[8.1]
  def change
    add_index :users_roles, :role_id, if_not_exists: true
  end
end
