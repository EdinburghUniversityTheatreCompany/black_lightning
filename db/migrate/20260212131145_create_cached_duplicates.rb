class CreateCachedDuplicates < ActiveRecord::Migration[8.1]
  def change
    create_table :cached_duplicates do |t|
      t.integer :user1_id, null: false
      t.integer :user2_id, null: false
      t.string :bucket_type, null: false

      t.timestamps

      t.index [ :user1_id, :user2_id ], unique: true
      t.index :bucket_type
    end

    add_foreign_key :cached_duplicates, :users, column: :user1_id
    add_foreign_key :cached_duplicates, :users, column: :user2_id
  end
end
