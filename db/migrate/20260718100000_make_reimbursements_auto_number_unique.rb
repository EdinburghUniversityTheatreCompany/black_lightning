class MakeReimbursementsAutoNumberUnique < ActiveRecord::Migration[8.1]
  # auto_number is the human-facing "Expense #N" label on review cards,
  # producer emails and the BACS draft — the model's MAX+1 assignment needs
  # the database to reject the concurrent-create race (the store retries on
  # RecordNotUnique). The table is empty until the cutover import, so the
  # index swap is safe to run in one step. NULLs (never produced in practice)
  # stay allowed — MySQL unique indexes permit them.
  def change
    remove_index :reimbursements_expenses, :auto_number
    add_index :reimbursements_expenses, :auto_number, unique: true
  end
end
