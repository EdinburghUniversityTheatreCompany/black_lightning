class AddDigitalProgrammeUrlToEvents < ActiveRecord::Migration[8.1]
  # A link out to the show's digital programme, wherever the producers put it
  # (a PDF in Drive, a Squarespace page, an Issuu embed). Nullable and blank for
  # every existing row: a programme is a per-show thing that most events -- a
  # workshop, a season, anything before this existed -- simply do not have, so
  # there is nothing to backfill and no constraint to add later.
  #
  # Stored on Event rather than Show because the box office screen picks from a
  # pool of Events and cannot know which subclass it drew.
  def change
    add_column :events, :digital_programme_url, :string, limit: 255
  end
end
