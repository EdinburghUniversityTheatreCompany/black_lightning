class AddImageColumnToShows < ActiveRecord::Migration
  def self.up
    add_attachment :shows, :image
  end

  def self.down
    remove_attachment :shows, :image
  end
end
