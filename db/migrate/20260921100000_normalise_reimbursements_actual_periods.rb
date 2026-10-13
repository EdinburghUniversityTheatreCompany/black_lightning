# Ran in production: it zero-padded every stored EUSA period. The one-off service it called
# (Reimbursements::PeriodNormalisation) is gone; the parser and EusaActual's before_validation keep
# new rows canonical. Kept as a no-op so the version still loads.
class NormaliseReimbursementsActualPeriods < ActiveRecord::Migration[8.1]
  def up
    say "nothing to do: the period backfill ran in production and its service has been removed"
  end

  # A no-op rather than irreversible, which would block an unrelated rollback past it.
  def down
    say "nothing to undo: the canonical period is what every write path produces"
  end
end
