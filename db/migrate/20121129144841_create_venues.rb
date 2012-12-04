class CreateVenues < ActiveRecord::Migration
  def change
    create_table :venues do |t|
      t.string :name
      t.string :tagline
      t.text :description
      t.string :location
      t.attachment :image

      t.timestamps
    end

    add_column :shows, :venue_id, :integer
  end
end
