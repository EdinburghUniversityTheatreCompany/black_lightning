class AddReimbursementsPersonForeignKeyToUsers < ActiveRecord::Migration[8.1]
  # Safe to add before the importer backfills: FK constraints ignore NULLs, so
  # this only guards values actually written (every reimbursements_person_id is
  # NULL until then — which is also why skipping existing-row validation via
  # foreign_key_checks=0 is sound). Kept separate from the column add per the
  # multi-step convention; the up/down shape is strong_migrations' recommended
  # MySQL pattern for adding an FK without blocking writes on both tables.
  def up
    safety_assured do
      execute "SET SESSION foreign_key_checks = 0"
      add_foreign_key :users, :reimbursements_people, column: :reimbursements_person_id
    ensure
      execute "SET SESSION foreign_key_checks = 1"
    end
  end

  def down
    remove_foreign_key :users, column: :reimbursements_person_id
  end
end
