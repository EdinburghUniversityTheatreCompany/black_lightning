module Reimbursements
  ##
  # One-off: gives every stored EUSA ledger row the canonical spelling of its period (see
  # Reconciliation.normalise_period), so the ledger filter stops offering "5" and "05" as two months.
  # A SERVICE rather than migration code because schema-loaded test DBs never run data migrations.
  module PeriodNormalisation
    # Idempotent: a canonical row is in none of the groups this writes. update_all per distinct value
    # deliberately bypasses EusaActual's before_validation: loading and saving every row to rewrite one
    # string column is what makes a backfill time out. Returns the number of ROWS rewritten.
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

    # Every distinct non-null period, compared in Ruby so "already canonical" stays the parser's rule
    # and is not restated in SQL.
    def self.stored_periods(scope)
      scope.where.not(period: nil).distinct.pluck(:period).compact
    end
    private_class_method :stored_periods
  end
end
