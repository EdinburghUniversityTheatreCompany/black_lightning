class AddIndexesToHabtmJoinTables < ActiveRecord::Migration[8.1]
  def change
    add_index :event_tags_events, :event_id
    add_index :event_tags_events, :event_tag_id

    add_index :mass_mails_users, :mass_mail_id
    add_index :mass_mails_users, :user_id

    add_index :attachment_tags_attachments, :attachment_id
    add_index :attachment_tags_attachments, :attachment_tag_id

    add_index :picture_tags_pictures, :picture_id
    add_index :picture_tags_pictures, :picture_tag_id
  end
end
