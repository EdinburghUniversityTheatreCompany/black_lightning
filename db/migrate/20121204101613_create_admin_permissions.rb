class CreateAdminPermissions < ActiveRecord::Migration
  def change
    create_table :admin_permissions do |t|
      t.string :name
      t.string :description
      t.string :action
      t.string :subject_class

      t.timestamps
    end

    create_table :permissions_roles do |t|
      t.integer :role_id
      t.integer :permission_id
    end
  end
end
