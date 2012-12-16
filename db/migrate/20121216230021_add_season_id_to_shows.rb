class AddSeasonIdToShows < ActiveRecord::Migration
  def change
    add_column :shows, :season_id, :integer
  end
end
