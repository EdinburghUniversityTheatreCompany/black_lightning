class DropMembershipActivationTokens < ActiveRecord::Migration[8.1]
  def change
    drop_table :membership_activation_tokens do |t|
      t.string :token
      t.references :user, null: true, foreign_key: true
      t.timestamps
    end
  end
end
