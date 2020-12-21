class AddAccessLevelToAttachments < ActiveRecord::Migration[6.0]
  def change
    add_column :attachments, :access_level, :int, null: false, default: 1
  end
end
