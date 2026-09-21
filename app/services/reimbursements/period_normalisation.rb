module Reimbursements
  ##
  # One-off: give every stored EUSA ledger row the canonical spelling of its
  # accounting period (see Reconciliation.normalise_period — zero-padded to two
  # digits).
  #
  # The period was stored verbatim from whatever the pasted sheet said, so the
  # ledger's own filter offered "05", "06", "5" and "6" as four different
  # months: `?period=6` returned 12 rows and `?period=06` five, and somebody
  # asking for September got two thirds of it with nothing on screen saying so.
  #
  # A SERVICE rather than migration code, for the reason AreaBackfill is one:
  # test and CI databases are schema-loaded, so a data migration never runs
  # there and could never be tested.
  module PeriodNormalisation
    # Idempotent: a row already in canonical form is not in any of the groups
    # this writes, and a second run finds nothing to do.
    #
    # Written with update_all per distinct value rather than row by row, so a
    # ledger of any size costs one UPDATE per spelling. That deliberately
    # bypasses EusaActual's own before_validation callback — which would do the
    # same thing — because loading and saving every row to rewrite one string
    # column is the shape that makes a backfill time out.
    #
    # Returns the number of ROWS rewritten, so the migration's log says what it
    # did.
    def self.run!(scope: EusaActual.all)
      rewritten = 0
      ActiveRecord::Base.transaction do
        stored_periods(scope).each do |stored|
          canonical = Reconciliation.normalise_period(stored)
          next if canonical == stored

          rewritten += scope.where(period: stored).update_all(period: canonical)
        end
      end
      rewritten
    end

    # Every distinct non-null period in the ledger. Pulled in one query and
    # compared in Ruby, because "which of these is already canonical" is the
    # same rule the parser applies and must not be restated in SQL.
    def self.stored_periods(scope)
      scope.where.not(period: nil).distinct.pluck(:period).compact
    end
    private_class_method :stored_periods
  end
end
