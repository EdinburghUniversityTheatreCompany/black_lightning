class CreateNews < ActiveRecord::Migration
  def change
    create_table :news do |t|
      t.string :title
      t.text :body
      t.string :slug
      t.date :publish_date
      t.boolean :show_public

      t.timestamps
    end
  end
end
