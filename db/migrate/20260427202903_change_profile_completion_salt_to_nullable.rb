class ChangeProfileCompletionSaltToNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :profile_completion_salt, true
  end
end
