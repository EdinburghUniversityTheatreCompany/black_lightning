class CreateShows < ActiveRecord::Migration
  def change
    create_table :shows do |t|
      t.string :name
      t.string :tagline
      t.string :slug
      t.text :description
      t.integer :xts_id

      t.timestamps
    end
  end
end
