class AddGroupToEditableBlock < ActiveRecord::Migration
  def change
    add_column :admin_editable_blocks, :group, :string
  end
end
