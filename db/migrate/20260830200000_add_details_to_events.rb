class AddDetailsToEvents < ActiveRecord::Migration[8.1]
  def change
    # All three were only ever written in prose inside publicity_text, where
    # nothing -- the box office screen, the event page, the schema.org output --
    # could read them.
    add_column :events, :duration_minutes, :integer
    add_column :events, :doors_open_minutes_before, :integer
    add_column :events, :age_guidance, :string, limit: 255
  end
end
