class AddPretixSyncStateToEvents < ActiveRecord::Migration[8.1]
  def change
    # When the series was last read successfully. Blank with the flag on means
    # the sync has never found anything yet, which the admin show page reports.
    add_column :events, :pretix_synced_at, :datetime
    # What stopped the last attempt, blank when it worked. A series that does not
    # exist yet is the ordinary case -- a producer ticks the box before building
    # the shop -- so it is recorded here and shown, never raised or reported.
    add_column :events, :pretix_sync_error, :string
  end
end
