class CreateAttachments < ActiveRecord::Migration
  def change
    create_table :attachments do |t|
      t.integer    :editable_block_id
      t.string     :name
      t.attachment :file

      t.timestamps
    end
  end
end
