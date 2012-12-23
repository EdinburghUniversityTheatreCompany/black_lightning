class RenameShowsToEvents < ActiveRecord::Migration
  def change
    rename_table :shows, :events
  end
end
