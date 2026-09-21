module Reimbursements
  ##
  # "Changes to the budget": one area's forecast log, its own revisions and
  # its lines' in one list, oldest first.
  #
  # A forecast row stores only the NEW amount, so "what changed" has to be
  # reconstructed by walking each line's own log in order from the figure it
  # started with. Doing that per line rather than across the area matters: two
  # lines revised at the same budget meeting are two independent sequences,
  # and reading them as one would report each new amount as a change from the
  # other line's.
  #
  # An area's own forecasts revise the show's AGREED TOTAL and its lines'
  # revise an allocation inside it, so each entry says which it was.
  class BudgetChanges
    Entry = Struct.new(:date, :subject, :area_total, :from, :to, :reason, :budget_update_id,
                       keyword_init: true) do
      # Whether this row revises the show's agreed total rather than one line.
      def area_total? = area_total

      # A first forecast against a line that started with no figure at all is
      # not a change from anything — it is somebody finally setting one.
      def first? = from.nil?
    end

    # Read off an area loaded through the store, whose own forecasts and whose
    # lines' forecasts are both preloaded.
    def self.for_area(area)
      entries = sequence(area.forecasts, area.initial_budget, area.name, area_total: true)
      area.budgets.each do |line|
        entries.concat(sequence(line.forecasts, line.initial_budget, line.name, area_total: false))
      end
      entries.sort_by { |entry| [ entry.date || Date.new(0), entry.subject.to_s ] }
    end

    # A loose line on its own: its own log, with no agreed total above it.
    def self.for_budget(budget)
      sequence(budget.forecasts, budget.initial_budget, budget.name, area_total: false)
    end

    # One owner's log, in date order, each row carrying the figure it replaced.
    def self.sequence(forecasts, initial, subject, area_total:)
      previous = initial
      ordered(forecasts).map do |forecast|
        entry = Entry.new(date: forecast.date || forecast.created_at&.to_date, subject: subject,
                          area_total: area_total, from: previous, to: forecast.amount,
                          reason: forecast.reason, budget_update_id: forecast.budget_update_id)
        previous = forecast.amount
        entry
      end
    end
    private_class_method :sequence

    # Oldest first, and never by id: a forecast log is edited and re-dated from
    # the budget edit page, so insertion order is not the order the committee
    # agreed things in.
    def self.ordered(forecasts)
      forecasts.sort_by { |forecast| [ forecast.date || forecast.created_at&.to_date || Date.new(0), forecast.id.to_i ] }
    end
    private_class_method :ordered
  end
end
