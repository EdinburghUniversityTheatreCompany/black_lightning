class RemoveDefaultProfileCompletionSalt < ActiveRecord::Migration[8.1]
  SHARED_DEFAULT_SALT = "d18bb80a91c253f6"

  def up
    # Backfill users stuck on the shared default salt so their tokens remain isolated
    User.where(profile_completion_salt: SHARED_DEFAULT_SALT).find_each do |user|
      user.update_column(:profile_completion_salt, SecureRandom.hex(8))
    end

    change_column_default :users, :profile_completion_salt, from: SHARED_DEFAULT_SALT, to: nil
  end

  def down
    change_column_default :users, :profile_completion_salt, from: nil, to: SHARED_DEFAULT_SALT
  end
end
