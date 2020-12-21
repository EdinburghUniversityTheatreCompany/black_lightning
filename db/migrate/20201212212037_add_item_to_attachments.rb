class AddItemToAttachments < ActiveRecord::Migration[6.0]
  def up
    add_reference :attachments, :item, polymorphic: true, index: true
  
    Attachment.all.each do |attachment|
      attachment.item_id = attachment.editable_block_id
      attachment.item_type = 'Admin::EditableBlock' if attachment.editable_block_id.present?
      
      attachment.save
    end

    # Leaves the editable block field because it's safer to throw that out once we're 100% sure the migration goes well.
  end

  def down
    remove_reference :attachments, :item, polymorphic: true
  end
end