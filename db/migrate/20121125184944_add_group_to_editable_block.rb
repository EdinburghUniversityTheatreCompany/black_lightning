class AddGroupToEditableBlock < ActiveRecord::Migration
  def change
    add_column :admin_editable_blocks, :group, :string
    add_column :admin_editable_blocks, :friendly_name, :string
  end
end
