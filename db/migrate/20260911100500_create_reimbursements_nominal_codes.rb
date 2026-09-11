class CreateReimbursementsNominalCodes < ActiveRecord::Migration[8.1]
  # One row per (cost centre, code) — that centre's own chart of accounts,
  # maintained by its finance admin. Two centres are two different EUSA
  # accounts, so the same code can recur under each without collision.
  #
  # cost_centre_id's FK is declared inline via t.references, not through
  # strong_migrations' SET SESSION foreign_key_checks workaround: the table
  # is brand new in this same migration, so strong_migrations never checks it
  # (see CreateReimbursementsAreas, which needed the workaround only for the
  # FK it added to the already-existing reimbursements_budgets).
  def up
    # charset/collation pinned explicitly, belt and braces alongside the
    # database.yml default: an unpinned create_table here would silently take
    # a different collation than every sibling reimbursements_* table, which
    # is not cosmetic — Task 4 compares this column against
    # reimbursements_budgets.nominal_code, and a cross-collation comparison
    # raises "Illegal mix of collations".
    create_table :reimbursements_nominal_codes, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.string :code, null: false
      t.string :label, null: false
      t.boolean :active, null: false, default: true
      t.references :cost_centre, type: :bigint, null: false, index: false,
                                 foreign_key: { to_table: :reimbursements_cost_centres }
      t.timestamps

      # index: false above: this composite already covers lookups by
      # cost_centre_id alone, so a separate single-column index would be dead
      # weight.
      t.index %i[cost_centre_id code], unique: true,
              name: "index_reimbursements_nominal_codes_on_centre_and_code"
    end
  end

  def down
    drop_table :reimbursements_nominal_codes
  end
end
