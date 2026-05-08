class AddParentsToRoles < ActiveRecord::Migration[8.1]
  def change
    create_join_table :parent, :role, column_options: { foreign_key: { to_table: :roles }, type: :integer }, table_name: :roles_parents
  end
end
