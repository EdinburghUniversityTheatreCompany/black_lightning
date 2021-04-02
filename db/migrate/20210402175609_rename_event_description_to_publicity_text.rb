class RenameEventDescriptionToPublicityText < ActiveRecord::Migration[6.0]
  def change
    rename_column :events, :description, :publicity_text
  end
end
