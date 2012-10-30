class CreateTechies < ActiveRecord::Migration
  def change
    create_table :techies do |t|
      t.string :name

      t.timestamps
    end
  end
end
