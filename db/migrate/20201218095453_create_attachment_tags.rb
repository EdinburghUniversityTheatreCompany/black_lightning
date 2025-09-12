class CreateAttachmentTags < ActiveRecord::Migration[6.0]
  def change
    create_table :attachment_tags do |t|
      t.string :name
      t.text :description

      t.timestamps
    end

    create_join_table :attachments, :attachment_tags
  end
end
