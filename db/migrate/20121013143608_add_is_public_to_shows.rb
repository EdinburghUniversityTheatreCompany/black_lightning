class AddIsPublicToShows < ActiveRecord::Migration
  def change
    add_column :shows, :is_public, :boolean
  end
end
