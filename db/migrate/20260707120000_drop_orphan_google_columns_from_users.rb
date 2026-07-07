class DropOrphanGoogleColumnsFromUsers < ActiveRecord::Migration[8.1]
  # Orphan columns: present in dev/test (and schema.rb) but never created by a
  # migration and never deployed to production. No code reads or writes them; only
  # length validations referenced them, crashing production
  # (`undefined method 'google_access_token'`) where the columns are absent.
  #
  # column_exists? makes `up` a no-op on production and `down` a no-op where the
  # columns already exist. Explicit up/down (not `change`) because an auto-reversed
  # `change` re-evaluates the guard against post-migration state and silently skips
  # re-adding the columns. safety_assured: the columns are empty everywhere they
  # exist and every reference is removed in this same change, so strong_migrations'
  # ignored_columns dance buys nothing.
  COLUMNS = {
    google_access_token: :text,
    google_refresh_token: :text,
    google_calendar_id: :string,
    google_token_expires_at: :datetime
  }.freeze

  def up
    safety_assured do
      COLUMNS.each_key do |name|
        remove_column :users, name if column_exists?(:users, name)
      end
    end
  end

  def down
    COLUMNS.each do |name, type|
      add_column :users, name, type unless column_exists?(:users, name)
    end
  end
end
