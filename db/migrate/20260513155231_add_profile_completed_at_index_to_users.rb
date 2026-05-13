class AddProfileCompletedAtIndexToUsers < ActiveRecord::Migration[8.1]
  def change
    add_index :users, :profile_completed_at, if_not_exists: true
  end
end
