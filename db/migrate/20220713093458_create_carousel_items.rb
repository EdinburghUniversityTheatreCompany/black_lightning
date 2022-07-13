class CreateCarouselItems < ActiveRecord::Migration[7.0]
  def change
    create_table :carousel_items do |t|
      t.string :title
      t.text :tagline
      t.boolean :is_active
      t.string :carousel_name
      t.integer :order

      t.timestamps
    end
  end
end
