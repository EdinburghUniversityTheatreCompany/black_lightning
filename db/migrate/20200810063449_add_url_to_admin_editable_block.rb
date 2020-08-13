class AddUrlToAdminEditableBlock < ActiveRecord::Migration[6.0]
  def change
    add_column :admin_editable_blocks, :url, :string
  end
end
