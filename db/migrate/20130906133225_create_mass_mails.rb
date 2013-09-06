class CreateMassMails < ActiveRecord::Migration
  def change
    create_table :mass_mails do |t|
      t.integer :sender_id
      t.string :subject
      t.text :body
      t.datetime :send_date
      t.boolean :draft

      t.timestamps
    end

    create_table :mass_mails_users do |t|
      t.integer :mass_mail_id
      t.integer :user_id
    end
  end
end
