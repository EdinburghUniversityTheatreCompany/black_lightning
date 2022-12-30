class AddOrderingToAttachmentTags < ActiveRecord::Migration[7.0]
  def change
    add_column :attachment_tags, :ordering, :bigint
  end
end
