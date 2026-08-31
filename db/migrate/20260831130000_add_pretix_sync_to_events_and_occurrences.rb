class AddPretixSyncToEventsAndOccurrences < ActiveRecord::Migration[8.1]
  def change
    # Nullable rather than `default: false, null: false`, matching pretix_shown
    # and is_public beside it: events is a populated legacy table, and nil reads
    # as false through the model's predicate anyway.
    add_column :events, :pretix_sync_performances, :boolean

    # pretix's own id for the subevent this row was synced from. NULL means the
    # row was typed by hand, which is the whole ownership model: the sync reads,
    # updates and deletes only the rows carrying an id.
    add_column :event_occurrences, :pretix_subevent_id, :bigint
    # pretix carries an admission time per date; the event-wide
    # doors_open_minutes_before is the fallback when this is blank.
    add_column :event_occurrences, :admission_at, :datetime
    # Written by the sync from best_availability_state.
    add_column :event_occurrences, :sold_out, :boolean
    # NEVER written by the sync -- pretix has no cancellation concept for a date,
    # and "not on sale yet" is indistinguishable from "pulled". A person sets this.
    add_column :event_occurrences, :cancelled, :boolean

    # MySQL permits many NULLs under a unique index, so this both enforces one row
    # per subevent and leaves hand-typed rows unconstrained.
    add_index :event_occurrences, :pretix_subevent_id, unique: true
  end
end
