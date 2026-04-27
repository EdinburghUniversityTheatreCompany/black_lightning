class AddProfileCompletionSaltToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :profile_completion_salt, :string

    # Generate unique salt for each existing user
    User.find_each do |user|
      user.update_column(:profile_completion_salt, SecureRandom.hex(8))
    end
  end

  def down
    remove_column :users, :profile_completion_salt
  end
end
