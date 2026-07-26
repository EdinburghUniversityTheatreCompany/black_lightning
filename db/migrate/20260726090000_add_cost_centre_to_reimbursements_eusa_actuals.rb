class AddCostCentreToReimbursementsEusaActuals < ActiveRecord::Migration[8.1]
  # Reconcile now attributes every pasted row to the cost centre named in the
  # export's own Cost Centre column, instead of filtering the whole paste down
  # to one centre and silently dropping the rest. That needs a real FK, the way
  # reimbursements_budgets already has one, so a row can be scoped, rolled up
  # and matched by cost centre rather than by string comparison at read time.
  #
  # The +cost_centre+ STRING column stays: it is what the export said, and the
  # audit trail wants that verbatim (including blank, when the export omits the
  # column and an operator assigns the rows by hand). +cost_centre_id+ is the
  # attribution; the string is the evidence.
  #
  # Nullable, because a historical row whose code matches no configured cost
  # centre — or that was imported with a blank code — genuinely has no centre,
  # and guessing one would file real spend under the wrong pot. The FK is added
  # in the next migration per the multi-step convention strong_migrations asks
  # for.
  def up
    add_reference :reimbursements_eusa_actuals, :cost_centre, type: :bigint, null: true, index: true

    # One statement, no row loop: the table is the imported EUSA ledger (low
    # thousands of rows at most) and every row is set from a join, so there is
    # nothing to batch. Case-insensitive to match how the parser compared codes.
    # Rows whose code matches nothing configured, and blank-code rows, are left
    # NULL on purpose — see the class comment.
    safety_assured do
      execute <<~SQL.squish
        UPDATE reimbursements_eusa_actuals AS a
        INNER JOIN reimbursements_cost_centres AS c
                ON UPPER(TRIM(a.cost_centre)) = UPPER(TRIM(c.eusa_code))
        SET a.cost_centre_id = c.id
        WHERE a.cost_centre_id IS NULL AND TRIM(a.cost_centre) <> ''
      SQL
    end
  end

  def down
    remove_reference :reimbursements_eusa_actuals, :cost_centre
  end
end
