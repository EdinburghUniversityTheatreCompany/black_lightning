class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :slug
      t.boolean :internal, null: false, default: false
      t.string :website

      t.timestamps
    end

    add_index :companies, :slug, unique: true
  end
end
