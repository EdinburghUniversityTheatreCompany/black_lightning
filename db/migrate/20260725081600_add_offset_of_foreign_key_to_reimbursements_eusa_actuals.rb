class AddOffsetOfForeignKeyToReimbursementsEusaActuals < ActiveRecord::Migration[8.1]
  # The self-referential offset_of_id FK, kept separate from the column add per
  # the multi-step convention. Safe to add straight away: FK constraints ignore
  # NULLs and every offset_of_id is NULL until the first offsetting pair is
  # applied, which is also why skipping existing-row validation via
  # foreign_key_checks=0 is sound. Same up/down shape as
  # AddReimbursementsPersonForeignKeyToUsers — strong_migrations' recommended
  # MySQL pattern for adding an FK without blocking writes on both tables.
  def up
    safety_assured do
      execute "SET SESSION foreign_key_checks = 0"
      add_foreign_key :reimbursements_eusa_actuals, :reimbursements_eusa_actuals,
                      column: :offset_of_id
    ensure
      execute "SET SESSION foreign_key_checks = 1"
    end
  end

  def down
    remove_foreign_key :reimbursements_eusa_actuals, column: :offset_of_id
  end
end
