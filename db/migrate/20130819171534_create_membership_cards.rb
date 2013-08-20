class CreateMembershipCards < ActiveRecord::Migration
  def change
    create_table :membership_cards do |t|
      t.string     :card_number
      t.integer    :user_id
      t.timestamps
    end
  end
end
