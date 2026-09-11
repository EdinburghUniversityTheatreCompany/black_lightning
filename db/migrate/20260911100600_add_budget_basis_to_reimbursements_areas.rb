class AddBudgetBasisToReimbursementsAreas < ActiveRecord::Migration[8.1]
  # What the area's agreed total is a total OF. A show gets a spend cap
  # ("expenses"): what it raises does not buy it more room. A committee gets a
  # net allowance ("net"): money it raises genuinely raises what it may spend.
  #
  # Defaulted to "expenses" with NO backfill pass: every area that exists came
  # from the Phase 1 backfill of show-shaped budget lines, and a spend cap is
  # the safer reading — it never reports more room than there is. A committee
  # area is then one deliberate choice by a human on the area form.
  #
  # Adding a column WITH a default is instant on MySQL 8.4 (the app pins
  # mysql:8.4 everywhere), so this needs no separate backfill.
  #
  # A string column added with no COLLATE clause inherits the TABLE's
  # collation, not the database's — probed on a throwaway table created
  # utf8mb4_0900_ai_ci inside a utf8mb4_unicode_ci database, where the new
  # column came out utf8mb4_0900_ai_ci. So this matches its siblings in
  # reimbursements_areas whatever the database default is, which is stronger
  # protection than config/database.yml's pin and a different mechanism from
  # it. The literals below are deliberately NOT Area::BASIS_EXPENSES: a
  # migration is frozen in time and must keep running after the constant is
  # renamed or removed.
  # ROLLING THIS BACK AND RE-MIGRATING RETURNS EVERY AREA TO A SPEND CAP.
  # The down drops the column and the up re-adds it with the default above, so
  # a committee area somebody declared a net allowance comes back declaring
  # nothing: its not-yet-allocated figure drops by the whole of its income with
  # no event on screen to explain it. Re-declare the net areas after any
  # rollback past this migration. The loss is in the conservative direction —
  # a spend cap leaves income out of Area#allocated, so the area reads as
  # having LESS room, never more, and Area#remaining is basis-free by design.
  #
  # It is NOT recorded the way names are (name_before_area_rename) and
  # membership is (area_before_rollback), and the reason is the ordering those
  # two depend on rather than a decision that the value is worth less. A
  # rollback reverts in DESCENDING version order, so this migration's down runs
  # FIRST: by the time BackfillReimbursementsAreas#down calls
  # AreaMembership.record!, this column is already gone (probed — after a bare
  # STEP=1 the areas and their budgets are all still there and
  # column_exists?(:reimbursements_areas, :budget_basis) is false). And a
  # STEP=1 rollback, which is the likeliest way to reach this at all, never
  # runs that recorder in the first place: only the backfill's down calls it.
  # So recording the basis needs a scratch column of its own on a table that
  # outlives the areas, written here and read back here — a migration, a
  # column and a service pass, not a key in a record that already exists.
  # Recorded for Phase 2c.
  def up
    add_column :reimbursements_areas, :budget_basis, :string, null: false, default: "expenses"
  end

  def down
    remove_column :reimbursements_areas, :budget_basis
  end
end
