class AddOrderNumberToAdminEditableBlock < ActiveRecord::Migration[6.0]
  def change
    add_column :admin_editable_blocks, :ordering, :bigint
  end
end
