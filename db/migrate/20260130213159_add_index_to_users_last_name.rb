class AddIndexToUsersLastName < ActiveRecord::Migration[8.1]
  def change
    add_index :users, :last_name
  end
end
