class AddAttachmentImageToNews < ActiveRecord::Migration
  def self.up
    change_table :news do |t|
      t.has_attached_file :image
    end
  end

  def self.down
    drop_attached_file :news, :image
  end
end
