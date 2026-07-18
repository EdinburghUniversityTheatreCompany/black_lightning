class AddReimbursementsPersonToUsers < ActiveRecord::Migration[8.1]
  # Real FK replacing the cached users.airtable_person_id string. Nullable —
  # the importer backfills it from airtable_person_id; the FK constraint is a
  # separate migration so this one stays a cheap metadata change.
  def change
    add_reference :users, :reimbursements_person, type: :bigint, null: true, index: true
  end
end
