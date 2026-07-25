class AddOffsetLinkingToReimbursementsEusaActuals < ActiveRecord::Migration[8.1]
  # Reconcile can now recognise an accrual and its reversal as one offsetting
  # pair. Both rows are still imported (finance needs the audit trail), so each
  # leg is stamped and pointed at its counterpart instead of being dropped.
  #
  # The offset_of_id foreign key is added separately (next migration) per the
  # multi-step convention strong_migrations asks for.
  def change
    # Nullable with no default: an unstamped row means "not part of an offset",
    # which is true of every row imported before this, so there is nothing to
    # backfill and no NOT NULL step to follow.
    add_column :reimbursements_eusa_actuals, :reconciliation_status, :string
    add_index :reimbursements_eusa_actuals, :reconciliation_status

    # Self-referential: both legs of a pair point at each other.
    add_reference :reimbursements_eusa_actuals, :offset_of, type: :bigint, null: true, index: true
  end
end
