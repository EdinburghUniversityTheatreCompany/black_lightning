module Reimbursements
  ##
  # Offsetting pairs among the ledger's unplaced rows, for a person to confirm: Reconcile's detector
  # sees one paste, so legs pasted months apart both sit unplaced. Every pair passing the
  # hand-pairing gate (EusaActual#offset_candidates) is listed, so every row with a possible partner
  # is held back from Link credits. A row can be marked in one pair only, so only its strongest
  # pair starts ticked, and only if the detector would propose it.
  #
  # shortcut: a pair someone unticked is proposed again on the next visit; store a "not a pair"
  # dismissal if finance ever marks one by accident.
  class LedgerOffsetPairs
    Pair = Data.define(:debit, :credit, :score, :ticked) do
      def key = "#{debit.id}:#{credit.id}"
      def row_ids = [ debit.id, credit.id ]
    end

    attr_reader :pairs

    def initialize(ledger)
      rows = ledger.select { |actual| actual.pairable? && actual.date }
      debits, credits = rows.partition { |actual| actual.signed_amount.positive? }
      credits_by_amount = credits.group_by { |credit| -credit.signed_amount }
      scored = debits.flat_map do |debit|
        debit.offset_candidates(credits_by_amount.fetch(debit.signed_amount, [])).map do |credit|
          [ debit, credit, Reconciliation.offset_pair_score(debit, credit) ]
        end
      end
      @pairs = grouped(ticked(scored))
    end

    def paired_ids = pairs.flat_map(&:row_ids).to_set

    private

    def ticked(scored)
      used = Set.new
      scored.sort_by { |debit, credit, score| [ -score, debit.id, credit.id ] }.map do |debit, credit, score|
        tick = [ debit.id, credit.id ].none? { |id| used.include?(id) }
        used.merge([ debit.id, credit.id ]) if tick
        Pair.new(debit:, credit:, score:, ticked: tick && score >= Reconciliation::OFFSET_MIN_SCORE)
      end
    end

    # A debit's pairs together, so a reader sees its rival credits side by side.
    def grouped(pairs) = pairs.group_by(&:debit).values.flatten
  end
end
