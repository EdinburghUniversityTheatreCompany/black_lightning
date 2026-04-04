class AddCalendarTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :calendar_token, :string
    add_index  :users, :calendar_token, unique: true
  end
end
