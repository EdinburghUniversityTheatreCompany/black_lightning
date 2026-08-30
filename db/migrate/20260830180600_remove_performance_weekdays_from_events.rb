class RemovePerformanceWeekdaysFromEvents < ActiveRecord::Migration[8.1]
  def change
    # Superseded by event_occurrences, which carry a real curtain time. Nothing
    # is backfilled: the one event that used this column plays intermittently and
    # is not currently running, and inventing curtain times for ~3000 archive
    # rows would state as fact something nobody recorded.
    safety_assured { remove_column :events, :performance_weekdays, :string, limit: 255 }
  end
end
