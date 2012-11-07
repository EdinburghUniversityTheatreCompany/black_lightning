class AddPerformanceDatesToShows < ActiveRecord::Migration
  def change
    add_column :shows, :start_date, :date
    add_column :shows, :end_date, :date
  end
end
