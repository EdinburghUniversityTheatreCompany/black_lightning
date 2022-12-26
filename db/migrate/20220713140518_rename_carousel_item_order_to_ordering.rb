class RenameCarouselItemOrderToOrdering < ActiveRecord::Migration[7.0]
  def change
    rename_column :carousel_items, :order, :ordering
  end
end
