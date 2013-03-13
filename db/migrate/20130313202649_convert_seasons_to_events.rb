class ConvertSeasonsToEvents < ActiveRecord::Migration
  # See http://guides.rubyonrails.org/migrations.html#using-models-in-your-migrations
  # for some guidance. This is not going to be nice...

  class Season < ActiveRecord::Base
    has_many :events
  end

  def up
    Season.reset_column_information
    Season.all.each do |season|
      attrs = season.attributes
      attrs.delete("id")
      attrs.delete("created_at")
      attrs.delete("updated_at")

      new_season = Event.new(attrs)
      new_season.type = "Season"
      new_season.save! # Throw an error if the save doesn't complete

      season.events.each do |event|
        event.season_id = new_season.id
        event.save!
      end
    end

    drop_table :seasons
  end

  def down
    create_table :seasons do |t|
      t.string :name
      t.string :slug
      t.text :description
      t.date :start_date
      t.date :end_date

      t.timestamps
    end

    Season.reset_column_information

    old_seasons = Event.where("type = 'Season'")
    old_seasons.all.each do |season|
      attrs = season.attributes
      attrs.delete("id")
      attrs.delete("created_at")
      attrs.delete("updated_at")

      new_season = Season.new(attrs)
      new_season.save!

      old_season.events.each do |event|
        event.season_id = new_season.id
        event.save!
      end
    end

    old_seasons.delete_all
  end
end
