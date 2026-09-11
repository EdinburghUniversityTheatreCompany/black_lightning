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
  def up
    add_column :reimbursements_areas, :budget_basis, :string, null: false, default: "expenses"
  end

  def down
    remove_column :reimbursements_areas, :budget_basis
  end
end
