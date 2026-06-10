class CreateDepartments < ActiveRecord::Migration[8.1]
  def change
    create_table :departments do |t|
      t.string :name, null: false
      t.text :match_terms
      t.integer :ordering

      t.timestamps
    end

    add_index :departments, :name, unique: true
  end
end
