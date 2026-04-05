class BackfillCalendarTokensForUsers < ActiveRecord::Migration[8.1]
  def up
    User.reset_column_information
    User.where(calendar_token: nil).find_each do |user|
      user.update_column(:calendar_token, SecureRandom.base58(24))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
