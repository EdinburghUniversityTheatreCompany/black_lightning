class AddAccessLevelToPictures < ActiveRecord::Migration[6.1]
  def change
    add_column :pictures, :access_level, :int, null: false, default: 2
  end
end
