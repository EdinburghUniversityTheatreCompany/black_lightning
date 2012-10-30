class AddTechieChildrenTable < ActiveRecord::Migration
  def change
    create_table :children_techies do |t|
      t.integer :techie_id
      t.integer :child_id

      t.timestamps
    end
  end
end
