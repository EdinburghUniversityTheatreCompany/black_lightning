class CreateReviews < ActiveRecord::Migration
  def change
    create_table :reviews do |t|
      t.integer :show_id
      t.string :reviewer
      t.text :body
      t.decimal :rating, :precision => 2, :scale => 1
      t.date :review_date

      t.timestamps
    end
  end
end
