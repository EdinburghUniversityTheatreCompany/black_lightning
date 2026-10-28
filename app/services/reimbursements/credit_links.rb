module Reimbursements
  ##
  # The ledger's unplaced credits that exactly one income budget claims (CreditBudgetMatcher), for
  # "Link credits". A credit in a proposed offsetting pair (LedgerOffsetPairs) is held back: the two
  # may be an accrual and its reversal, and linking one leg counts income that never arrived.
  class CreditLinks
    Link = Struct.new(:actual, :budget)

    attr_reader :links, :held_back

    # +actuals+ are the rows on screen; +paired_ids+ the rows in a proposed offsetting pair.
    def initialize(actuals:, paired_ids:, matcher:)
      @links = []
      @held_back = []
      # An undated row has no year to judge, so a person places it.
      actuals.select { |actual| actual.apportionable? && actual.date }.each do |actual|
        centre = matcher.cost_centre_of(actual)
        budget = centre && matcher.budget_for(actual, centre)
        next unless budget

        if paired_ids.include?(actual.id)
          @held_back << actual
        else
          @links << Link.new(actual, budget)
        end
      end
    end

    # [budget, credits] pairs, for the summary above the button.
    def by_budget = links.group_by(&:budget).transform_values { |group| group.map(&:actual) }
  end
end
