class AddGalleries < ActiveRecord::Migration
  def change
    create_table :pictures do |t|
      t.text    :description
      t.integer :gallery_id
      t.string  :gallery_type

      t.attachment :image

      t.timestamps
    end
  end
end
