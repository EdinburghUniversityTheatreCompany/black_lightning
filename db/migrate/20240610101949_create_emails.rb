class CreateEmails < ActiveRecord::Migration[7.1]
  def change
    create_table :emails do |t|
      t.string :email
      t.references :attached_object, null: false, polymorphic: true, index: true

      t.timestamps

      t.index [:email, :attached_object_id], unique: true
    end
  end
end
