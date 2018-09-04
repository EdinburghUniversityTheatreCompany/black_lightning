class CreateMembershipActivationTokens < ActiveRecord::Migration
  def change
    create_table :membership_activation_tokens do |t|
      t.string   "uid",        limit: 255
      t.string   "token",      limit: 255
      t.references :user, index: true, foreign_key: true

      t.timestamps null: false
    end
  end
end
