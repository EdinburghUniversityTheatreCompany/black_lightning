class CreateAdminEditableBlocks < ActiveRecord::Migration
  def change
    create_table :admin_editable_blocks do |t|
      t.string :name
      t.text :content

      t.timestamps
    end
  end
end
