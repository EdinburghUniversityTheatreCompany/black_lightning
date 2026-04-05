class AddCalendarEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :calendar_email, :string
  end
end
