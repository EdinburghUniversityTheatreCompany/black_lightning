class AddSlugToAdminStaffings < ActiveRecord::Migration
  def change
    add_column :admin_staffings, :slug, :string
    add_index :admin_staffings, :slug

    reversible do |direction|
      direction.up { Admin::Staffing.initialize_urls }
    end
  end
end
