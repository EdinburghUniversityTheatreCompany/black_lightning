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
  # mysql:8.4 everywhere), so this needs no separate backfill. The collation
  # is the table's own — inherited, like every sibling string column here,
  # from the utf8mb4_unicode_ci config/database.yml pins.
  def up
    add_column :reimbursements_areas, :budget_basis, :string, null: false, default: "expenses"
  end

  def down
    remove_column :reimbursements_areas, :budget_basis
  end
end
