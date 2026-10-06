module Reimbursements
  ##
  # The Budget, Spent, Waiting for approval and Left figures for one area or one budget line,
  # derived once so a row can never disagree with the total above it.
  #
  # Left is NOT Budget#remaining / Area#remaining: those ignore claims still waiting for
  # approval (finance's overspent question), while an owner asking "can my show afford this?"
  # counts them as spent. It is a new figure rather than a change to `remaining`, which the
  # budgets index, overview, exports and over-budget badge all read.
  #
  # Income lines are left out (expense and income are never totalled together), except
  # +unallocated+, which is Area#unallocated and so basis-aware.
  class SpendSummary
    attr_reader :budget_amount, :spent, :waiting, :unallocated

    def self.for_budget(budget)
      new(budget_amount: budget.no_budget_set? ? nil : budget.projected_amount,
          spent: budget.committed_amount,
          waiting: budget.pipeline_amount)
    end

    # The comparator is the area's agreed total where it has one, else what its expense lines
    # add up to (+from_lines?+), so the screen can say which. Read off an area loaded through
    # the store, never off budget.area.
    def self.for_area(area)
      lines = area.budgets.reject(&:income?)
      agreed = area.no_budget_set? ? nil : area.projected_amount
      new(budget_amount: agreed || line_total(lines),
          spent: lines.sum { |line| line.committed_amount || 0 },
          waiting: lines.sum { |line| line.pipeline_amount || 0 },
          from_lines: agreed.nil? && !line_total(lines).nil?,
          unallocated: area.unallocated)
    end

    # Nil when no line carries a figure. A line whose plan is unset is skipped, not counted as
    # zero (PlannedAmount), so unbudgeted lines report no budget rather than a £0 cap.
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

    # Nil, never zero, when nobody set a budget: 0 reads as "fully spent".
    def left
      return nil if budget_amount.nil?

      budget_amount - spent - waiting
    end

    def no_budget_set? = budget_amount.nil?

    def from_lines? = @from_lines

    def over? = !left.nil? && left.negative?

    # Positive, because "£2,426.13 over" is how it is written on screen.
    def over_by = over? ? -left : nil

    # A £0 budget would divide by zero, and a bar of nothing says nothing.
    def bar?
      !budget_amount.nil? && budget_amount.positive?
    end

    # The larger of the budget and what is spent and claimed, so an overspent bar fills
    # rather than overflowing its track.
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
