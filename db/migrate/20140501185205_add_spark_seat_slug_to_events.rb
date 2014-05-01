class AddSparkSeatSlugToEvents < ActiveRecord::Migration
  def change
    add_column :events, :spark_seat_slug, :string
  end
end
