class AddProfileCompletedAtIndexToUsers < ActiveRecord::Migration[8.1]
  def change
    add_index :users, :profile_completed_at
  end
end
