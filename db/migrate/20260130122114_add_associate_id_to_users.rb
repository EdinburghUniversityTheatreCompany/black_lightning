class AddAssociateIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :associate_id, :string
    add_index :users, :associate_id
  end
end
