class AddOrderingToEventTags < ActiveRecord::Migration[7.0]
  def change
    add_column :event_tags, :ordering, :bigint
  end
end
