class AddCompositeIndexToCarouselItems < ActiveRecord::Migration[8.1]
  def change
    add_index :carousel_items, [ :is_active, :ordering ]
  end
end
