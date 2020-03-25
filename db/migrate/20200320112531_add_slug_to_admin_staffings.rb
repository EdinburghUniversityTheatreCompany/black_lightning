class AddSlugToAdminStaffings < ActiveRecord::Migration
  def change
    add_column :admin_staffings, :slug, :string
    add_index :admin_staffings, :slug
  end
end
