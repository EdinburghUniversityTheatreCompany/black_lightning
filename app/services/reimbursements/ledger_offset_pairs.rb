module Reimbursements
  ##
  # Offsetting pairs among the ledger's unplaced rows, for a person to confirm. Reconcile's detector
  # sees one paste at a time, so an accrual and its reversal pasted in different months both sit
  # unplaced. Same hard gates and scoring (Reconciliation.detect_offsetting_pairs): proposals stay
  # conservative, as a ticked pair is hidden from every total.
  #
  # shortcut: a pair someone unticked is proposed, ticked, again on the next visit; store a "not a
  # pair" dismissal if finance ever marks one by accident.
  class LedgerOffsetPairs
    Pair = Struct.new(:debit, :credit, :score) do
      def key = "#{debit.id}:#{credit.id}"
    end

    # The detector's row over a stored one: blank amounts read as zero, the centre as its id.
    Row = Struct.new(:actual) do
      delegate :nominal_code, :ref, :period, :narrative, :narrative_1, :net, :date, to: :actual

      def debit = actual.debit || 0
      def credit = actual.credit || 0
      def cost_centre = actual.cost_centre_id&.to_s
    end

    attr_reader :pairs

    def initialize(ledger)
      rows = ledger.select { |actual| actual.pairable? && actual.date }
      found = Reconciliation.detect_offsetting_pairs(rows.map { |actual| Row.new(actual) })
      @pairs = found.map { |pair| Pair.new(rows[pair.debit_index], rows[pair.credit_index], pair.score) }
    end
  end
end
