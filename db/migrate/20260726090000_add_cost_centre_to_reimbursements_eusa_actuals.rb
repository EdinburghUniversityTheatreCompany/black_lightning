class AddCostCentreToReimbursementsEusaActuals < ActiveRecord::Migration[8.1]
  # Reconcile now attributes every pasted row to the cost centre named in the
  # export's own Cost Centre column, instead of filtering the whole paste down
  # to one centre and silently dropping the rest. That needs a real FK, the way
  # reimbursements_budgets already has one, so a row can be scoped, rolled up
  # and matched by cost centre rather than by string comparison at read time.
  #
  # The old +cost_centre+ STRING column goes with it. Nothing ever read it — the
  # exported code lives on in the parser's ActualsRow, which is where attribution
  # needs it, and only the persisted copy is redundant once the FK exists.
  # Keeping both would invite the two disagreeing, and it would cost the natural
  # name: an association called +cost_centre+ shadows a string column's reader
  # AND writer, so every import would try to assign "F40" to a belongs_to.
  #
  # cost_centre_id is nullable because a row with no cost centre is a real state
  # (see the backfill), and guessing one would file real spend under the wrong
  # pot. The FK is added in the next migration per the multi-step convention
  # strong_migrations asks for.
  def up
    add_reference :reimbursements_eusa_actuals, :cost_centre, type: :bigint, null: true, index: true

    # Every historical row in this ledger is Fringe spend, and F40 is both the
    # only configured cost centre and the first by id, so the answer is simply
    # "the first cost centre". Reading the old string only to arrive at the same
    # place would be ceremony, so this is one statement and no row loop.
    #
    # No cost centre configured at all is a fresh install, which has no actuals
    # rows to attribute either: a no-op, not an error.
    first_cost_centre_id = select_value("SELECT id FROM reimbursements_cost_centres ORDER BY id LIMIT 1")
    if first_cost_centre_id
      update("UPDATE reimbursements_eusa_actuals SET cost_centre_id = #{first_cost_centre_id.to_i}")
    end

    safety_assured { remove_column :reimbursements_eusa_actuals, :cost_centre }
  end

  # Recoverable, not merely reversible: the restored column is REPOPULATED from
  # the cost centre each row now points at, so a rollback hands back a working
  # column of real codes rather than an empty one. A row with no cost centre gets
  # "", which is exactly what such a row would have carried.
  #
  # Lossy in one direction only: a code the export printed that matched no
  # configured cost centre cannot come back, because after this migration nothing
  # stores it. There is no such row in this database — every row is F40.
  def down
    add_column :reimbursements_eusa_actuals, :cost_centre, :string, null: false, default: ""
    execute <<~SQL.squish
      UPDATE reimbursements_eusa_actuals AS a
      INNER JOIN reimbursements_cost_centres AS c ON c.id = a.cost_centre_id
      SET a.cost_centre = c.eusa_code
    SQL
    remove_reference :reimbursements_eusa_actuals, :cost_centre
  end
end
