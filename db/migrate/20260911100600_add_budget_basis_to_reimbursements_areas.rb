class AddBudgetBasisToReimbursementsAreas < ActiveRecord::Migration[8.1]
  # What the area's agreed total is a total OF — a spend cap or a net
  # allowance, the two Area::BASIS_LABELS name.
  #
  # Defaulted to "expenses" with NO backfill pass: every area that exists came
  # from the Phase 1 backfill of show-shaped budget lines, and a spend cap
  # never reports more room than there is. A committee area is then one
  # deliberate choice by a human on the area form. Adding a column WITH a
  # default is instant on MySQL 8.4, which the app pins everywhere.
  #
  # A string column added with no COLLATE clause inherits the TABLE's
  # collation, not the database's — probed on a throwaway table created
  # utf8mb4_0900_ai_ci inside a utf8mb4_unicode_ci database. So this matches
  # its siblings whatever the database default is: a different mechanism from
  # config/database.yml's pin, not the same one twice. The literals below are
  # deliberately NOT Area::BASIS_EXPENSES — a migration is frozen in time and
  # must keep running after the constant is renamed.
  #
  # ROLLING THIS BACK AND RE-MIGRATING RETURNS EVERY AREA TO A SPEND CAP.
  # The down drops the column and the up re-adds it with the default above, so
  # a committee area somebody declared a net allowance comes back declaring
  # nothing: its not-yet-allocated figure drops by the whole of its income with
  # no event on screen to explain it. Re-declare the net areas after any
  # rollback past this migration. The loss is conservative — a spend cap leaves
  # income out of Area#allocated, so the area reads as having LESS room, never
  # more.
  #
  # It is NOT recorded the way names are (name_before_area_rename) and
  # membership is (area_before_rollback), and the reason is ordering rather
  # than worth. A rollback reverts in DESCENDING version order, so this down
  # runs FIRST: by the time BackfillReimbursementsAreas#down calls
  # AreaMembership.record!, this column is already gone (probed — after a bare
  # STEP=1 the areas and their budgets are all still there and
  # column_exists?(:reimbursements_areas, :budget_basis) is false). And a
  # STEP=1 rollback, the likeliest way here, never runs that recorder at all.
  # Recording the basis therefore needs a scratch column of its own, written
  # and read back here — not a key in a record that already exists. Phase 2c.
  def up
    add_column :reimbursements_areas, :budget_basis, :string, null: false, default: "expenses"
  end

  def down
    remove_column :reimbursements_areas, :budget_basis
  end
end
