module Reimbursements
  ##
  # Offsetting pairs among the ledger's unplaced rows, for a person to confirm: Reconcile's detector
  # sees one paste, so legs pasted months apart both sit unplaced. Every pair passing the
  # hand-pairing gate (EusaActual#offset_candidates) is listed, so every row with a possible partner
  # is held back from Link credits; only each row's strongest pair, if the detector would propose
  # it, starts ticked.
  #
  # shortcut: a pair someone unticked is proposed again on the next visit; store a "not a pair"
  # dismissal if finance ever marks one by accident.
  class LedgerOffsetPairs
    Pair = Struct.new(:debit, :credit, :score, :ticked) do
      def key = "#{debit.id}:#{credit.id}"
      def row_ids = [ debit.id, credit.id ]
    end

    attr_reader :pairs

    def initialize(ledger)
      rows = ledger.select { |actual| actual.pairable? && actual.date }
      debits, credits = rows.partition { |actual| actual.signed_amount.positive? }
      credits_by_amount = credits.group_by { |credit| -credit.signed_amount }
      @pairs = debits.flat_map do |debit|
        debit.offset_candidates(credits_by_amount.fetch(debit.signed_amount, [])).map do |credit|
          Pair.new(debit, credit, Reconciliation.offset_pair_score(debit, credit), false)
        end
      end.sort_by { |pair| [ -pair.score, pair.debit.id, pair.credit.id ] }
      tick_strongest
    end

    def paired_ids = pairs.flat_map(&:row_ids).to_set

    private

    # A row can be marked in one pair only, so of its pairs only the strongest may start ticked.
    def tick_strongest
      used = Set.new
      pairs.each do |pair|
        next if pair.row_ids.any? { |id| used.include?(id) }

        used.merge(pair.row_ids)
        pair.ticked = pair.score >= Reconciliation::OFFSET_MIN_SCORE
      end
    end
  end
end
