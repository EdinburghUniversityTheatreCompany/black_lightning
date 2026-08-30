class CreateEventOccurrences < ActiveRecord::Migration[8.1]
  def change
    # Stated explicitly: every other table in this schema is utf8mb4_unicode_ci,
    # and without this the table takes the migrating server's default (8.0's
    # utf8mb4_0900_ai_ci here), so a later join or comparison against another
    # table's string column raises "Illegal mix of collations".
    create_table :event_occurrences, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      # events.id is a legacy INTEGER primary key, not a bigint. A bigint foreign
      # key here aborts the migration with a column-type mismatch.
      t.references :event, null: false, foreign_key: true, type: :integer, index: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.json :access_flags
      t.string :note

      t.timestamps

      # Declared inside create_table rather than as a standalone add_index: beside
      # a foreign key, a separate add_index makes create_table irreversible.
      t.index [ :event_id, :starts_at ]
    end
  end
end
