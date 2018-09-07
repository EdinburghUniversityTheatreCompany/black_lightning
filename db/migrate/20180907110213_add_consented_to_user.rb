class AddConsentedToUser < ActiveRecord::Migration
  def change
    add_column :users, :consented, :date
  end
end
