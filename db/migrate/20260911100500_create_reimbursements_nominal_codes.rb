class CreateReimbursementsNominalCodes < ActiveRecord::Migration[8.1]
  # One row per (cost centre, code) — that centre's own chart of accounts,
  # maintained by its finance admin. Two centres are two different EUSA
  # accounts, so the same code can recur under each without collision.
  #
  # cost_centre_id's FK is declared inline via t.references, not through
  # strong_migrations' SET SESSION foreign_key_checks workaround: that
  # workaround is for adding an FK to an ALREADY-POPULATED table (see
  # CreateReimbursementsAreas, which needed it for
  # reimbursements_budgets.area_id). reimbursements_nominal_codes is brand
  # new in this same migration and therefore guaranteed empty, which
  # strong_migrations exempts outright regardless of whether the REFERENCED
  # table (reimbursements_cost_centres) already has rows.
  def up
    # charset/collation pinned explicitly: this table's own migration doesn't
    # otherwise say, so a fresh CREATE TABLE takes the SERVER's default
    # collation — and on this MySQL 8 server that default is
    # utf8mb4_0900_ai_ci, not the utf8mb4_unicode_ci every sibling
    # reimbursements_* table carries (set back when the database itself
    # defaulted to it). Without this, code's case/accent folding — the whole
    # basis for the model's case_sensitive: false uniqueness validation —
    # would run under a DIFFERENT collation than the rest of this schema,
    # and a freshly created database (a new worktree, a rebuilt CI runner)
    # would silently diverge from one restored via db:schema:load.
    create_table :reimbursements_nominal_codes, charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.string :code, null: false
      t.string :label, null: false
      t.boolean :active, null: false, default: true
      t.references :cost_centre, type: :bigint, null: false, index: false,
                                 foreign_key: { to_table: :reimbursements_cost_centres }
      t.timestamps

      # Unique within a centre, not globally — the whole point of this table.
      # Leads with cost_centre_id, so it also serves lookups by centre alone
      # (hence index: false on the reference above, which would otherwise
      # duplicate this index's leading column).
      t.index %i[cost_centre_id code], unique: true,
              name: "index_reimbursements_nominal_codes_on_centre_and_code"
    end
  end

  def down
    drop_table :reimbursements_nominal_codes
  end
end
