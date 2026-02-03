class AddProfileCompletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :profile_completed_at, :datetime, null: true

    reversible do |dir|
      dir.up do
        # Backfill: existing consented users are already "complete"
        # Use consented date if available, otherwise created_at for users who have consented
        execute <<-SQL
          UPDATE users
          SET profile_completed_at = COALESCE(consented, created_at)
          WHERE consented IS NOT NULL
        SQL
      end
    end
  end
end
