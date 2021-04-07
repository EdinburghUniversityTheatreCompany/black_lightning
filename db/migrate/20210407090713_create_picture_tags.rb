class CreatePictureTags < ActiveRecord::Migration[6.1]
  def change
    create_table :picture_tags do |t|
      t.string :name
      t.text :description
      
      t.timestamps
    end

    create_join_table :pictures, :picture_tags
  end
end
