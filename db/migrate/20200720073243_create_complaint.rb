class CreateComplaint < ActiveRecord::Migration[6.0]
  def change
    create_table :complaints do |t|
      t.string :subject
      t.text :description

      t.boolean :resolved

      t.text :comments

      t.timestamps
    end
  end
end
