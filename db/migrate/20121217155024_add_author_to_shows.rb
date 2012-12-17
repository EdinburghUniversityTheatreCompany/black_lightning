class AddAuthorToShows < ActiveRecord::Migration
  def change
    add_column :shows, :author, :string
  end
end
