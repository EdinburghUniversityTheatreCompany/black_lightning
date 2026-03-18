class AddVersionNoteToVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :versions, :version_note, :string
  end
end
