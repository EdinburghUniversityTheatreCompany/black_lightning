class CreateVideoLinks < ActiveRecord::Migration[6.0]
  def change
    create_table :video_links do |t|
      t.string :name, null: false
      t.string :link, null: false
      t.integer :access_level, null: false, default: 1
      t.integer :order

      t.references :item, polymorphic: true, index: true

      t.timestamps
    end
  end
end
