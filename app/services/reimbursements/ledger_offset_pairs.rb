module Reimbursements
  ##
  # Offsetting pairs among the ledger's unplaced rows, for a person to confirm: Reconcile's detector
  # sees one paste, so legs pasted months apart both sit unplaced. Candidates pass the hand-pairing
  # gate (EusaActual#offset_candidates); the detector's score decides which start ticked.
  #
  # shortcut: a pair someone unticked is proposed again on the next visit; store a "not a pair"
  # dismissal if finance ever marks one by accident.
  class LedgerOffsetPairs
    Pair = Struct.new(:debit, :credit, :score) do
      def key = "#{debit.id}:#{credit.id}"
      def strong? = score >= Reconciliation::OFFSET_MIN_SCORE
      def row_ids = [ debit.id, credit.id ]
    end

    attr_reader :pairs

    def initialize(ledger)
      rows = ledger.select { |actual| actual.pairable? && actual.date }
      debits, credits = rows.partition { |actual| actual.signed_amount.positive? }
      credits_by_amount = credits.group_by { |credit| -credit.signed_amount }
      @pairs = pick(debits.flat_map do |debit|
        debit.offset_candidates(credits_by_amount.fetch(debit.signed_amount, [])).map do |credit|
          Pair.new(debit, credit, Reconciliation.offset_pair_score(debit, credit))
        end
      end)
    end

    def paired_ids = pairs.flat_map(&:row_ids).to_set

    private

    def pick(candidates)
      used = Set.new
      candidates.sort_by { |pair| [ -pair.score, pair.debit.id, pair.credit.id ] }.select do |pair|
        next false if pair.row_ids.any? { |id| used.include?(id) }

        used.merge(pair.row_ids)
      end
    end
  end
end
