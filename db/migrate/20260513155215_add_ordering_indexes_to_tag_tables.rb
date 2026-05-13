class AddOrderingIndexesToTagTables < ActiveRecord::Migration[8.1]
  def change
    add_index :attachment_tags, :ordering, if_not_exists: true
    add_index :event_tags, :ordering, if_not_exists: true
    add_index :admin_editable_blocks, :ordering, if_not_exists: true
  end
end
