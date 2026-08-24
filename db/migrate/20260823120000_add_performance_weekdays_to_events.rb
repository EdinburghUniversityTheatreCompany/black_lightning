class AddPerformanceWeekdaysToEvents < ActiveRecord::Migration[8.1]
  # Which days an event actually performs, as Date#wday integers (0 = Sunday),
  # comma separated. NULL means every day of the run -- which is exactly what a
  # bare date range has always meant here, so no existing row needs backfilling
  # and nobody has to invent performance days they do not know.
  #
  # This has to be stored because duration cannot answer "is it on tonight":
  # the Improverts run all year and play Fridays, while a three-week Fringe run
  # is also a long range and genuinely is on every night.
  def change
    add_column :events, :performance_weekdays, :string, limit: 255
  end
end
