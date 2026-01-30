class AddNotDuplicateUserIdsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :not_duplicate_user_ids, :json
  end
end
