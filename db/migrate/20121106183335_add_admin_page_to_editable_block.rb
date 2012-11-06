class AddAdminPageToEditableBlock < ActiveRecord::Migration
  def change
    add_column :admin_editable_blocks, :admin_page, :boolean
  end
end
