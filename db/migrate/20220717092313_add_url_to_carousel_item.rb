class AddUrlToCarouselItem < ActiveRecord::Migration[7.0]
  def change
    add_column :carousel_items, :url, :string
  end
end
