class CreateEmails < ActiveRecord::Migration[7.0]
  def change
    create_table :emails do |t|
      t.string :email
      t.references :attached_object, null: false, polymorphic: true, index: true

      t.timestamps

      t.index [:email, :attached_object_id, :attached_object_type], unique: true, name: 'index_emails_on_email_and_attached_object'
    end
  end
end
