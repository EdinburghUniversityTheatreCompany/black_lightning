module Reimbursements
  ##
  # The four figures the area page and My Budgets print for one area or one
  # budget line: Budget, Spent, Waiting for approval and Left.
  #
  # ONE derivation, because the same four numbers are printed in three places
  # (a landing row, the area's headline figures, and every line's row) and a
  # row that disagreed with the total above it is the failure this exists to
  # stop.
  #
  # **Left is NOT Budget#remaining / Area#remaining.** Those two answer
  # "what is left against what we have committed", and deliberately ignore
  # claims still waiting for approval — the figure finance needs when deciding
  # whether a line is overspent. An OWNER is asking a different question ("can
  # my show afford this?"), and money a producer has already claimed is spent
  # as far as that question goes. So Left subtracts the pipeline too, and is a
  # new figure with its own name rather than a change to `remaining`, which the
  # budgets index, the overview, the exports and the over-budget badge all read.
  #
  # **Income lines are left out entirely.** Expense and income are never
  # totalled together in this portal, so an area's Budget/Spent/Waiting/Left
  # cover its EXPENSE lines only; its income lines get their own small table.
  # The exception is +unallocated+, which is read straight off Area#unallocated
  # so the page can never disagree with the area edit card — that figure IS
  # basis-aware (a net area subtracts its income), and it is the area's own
  # statement about its agreed total rather than a spend figure.
  class SpendSummary
    attr_reader :budget_amount, :spent, :waiting, :unallocated

    # One budget line on its own — a loose line on My Budgets, or a row of the
    # area page's lines table.
    def self.for_budget(budget)
      new(budget_amount: budget.no_budget_set? ? nil : budget.projected_amount,
          spent: budget.committed_amount,
          waiting: budget.pipeline_amount)
    end

    # A whole area. The comparator is its AGREED TOTAL where it has one; where
    # it has not, what its expense lines add up to, marked as such
    # (+from_lines?+) so the screen can say where the figure came from rather
    # than presenting a sum of lines as a total somebody agreed.
    #
    # Read off an area loaded through the store (whose budgets, and their
    # expenses and forecasts, are preloaded) — never off budget.area.
    def self.for_area(area)
      lines = area.budgets.reject(&:income?)
      agreed = area.no_budget_set? ? nil : area.projected_amount
      new(budget_amount: agreed || line_total(lines),
          spent: lines.sum { |line| line.committed_amount || 0 },
          waiting: lines.sum { |line| line.pipeline_amount || 0 },
          from_lines: agreed.nil? && !line_total(lines).nil?,
          unallocated: area.unallocated)
    end

    # What the lines add up to, or nil when not one of them carries a figure.
    # A line whose own plan is unset is SKIPPED rather than counted as zero
    # (PlannedAmount), so an area of unbudgeted lines reports no budget at all
    # instead of a £0 cap everything is over.
    def self.line_total(lines)
      amounts = lines.reject(&:no_budget_set?).filter_map(&:projected_amount)
      amounts.empty? ? nil : amounts.sum
    end
    private_class_method :line_total

    def initialize(budget_amount:, spent:, waiting:, from_lines: false, unallocated: nil)
      @budget_amount = budget_amount
      @spent = spent || 0
      @waiting = waiting || 0
      @from_lines = from_lines
      @unallocated = unallocated
    end

    # Budget − Spent − Waiting. Nil, never zero, when nobody set a budget: a 0
    # there reads as "fully spent", which is a different and much louder claim.
    def left
      return nil if budget_amount.nil?

      budget_amount - spent - waiting
    end

    def no_budget_set? = budget_amount.nil?

    # Whether the comparator is a sum of the lines rather than an agreed total.
    def from_lines? = @from_lines

    def over? = !left.nil? && left.negative?

    # How much MORE than the budget has been spent and claimed — a positive
    # figure, because "£2,426.13 over" is how it is written on screen and a
    # bare negative reads as bad news twice.
    def over_by = over? ? -left : nil

    # Whether there is anything to draw a bar against. A £0 budget would divide
    # by zero, and a bar of nothing says nothing.
    def bar?
      !budget_amount.nil? && budget_amount.positive?
    end

    # The bar's scale: the budget, or the whole of what has been spent and
    # claimed where that is more, so an overspent bar fills rather than
    # overflowing its track.
    def bar_scale = [ budget_amount, spent + waiting ].max

    def spent_percentage = percentage(spent)

    def waiting_percentage = percentage(waiting)

    private

    def percentage(part)
      return 0 unless bar?

      scale = bar_scale
      return 0 if scale.zero?

      ((part / scale.to_d) * 100).to_f.round(1)
    end
  end
end
