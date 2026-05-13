class AddOrderingIndexesToTagTables < ActiveRecord::Migration[8.1]
  def change
    add_index :attachment_tags, :ordering
    add_index :event_tags, :ordering
    add_index :admin_editable_blocks, :ordering
  end
end
