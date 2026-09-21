class NormaliseReimbursementsActualPeriods < ActiveRecord::Migration[8.1]
  def up
    rewritten = Reimbursements::PeriodNormalisation.run!
    say "normalised the EUSA period on #{rewritten} ledger row(s)"
  end

  # Deliberately a no-op rather than irreversible.
  #
  # Nothing is lost going forward: "06" and "6" name the same EUSA month, and
  # the unpadded spelling was never read by anything — it was only ever typed
  # into a filter and compared. There is therefore no original to put back that
  # anybody could tell from the current value.
  #
  # Un-padding would also be actively wrong, because a rollback reverts the
  # SCHEMA and not the code: EusaActual's before_validation and the reconcile
  # parser would both go on writing the canonical form, so the ledger would
  # split back into two spellings of one month — the exact state this closed.
  def down
    say "nothing to undo: the canonical period is what every write path now produces"
  end
end
