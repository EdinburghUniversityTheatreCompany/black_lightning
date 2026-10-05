module Reimbursements
  ##
  # An area's forecast log, its own revisions (of the agreed total) and its
  # lines', oldest first. A forecast stores only the new amount, so each line's
  # log is walked on its own: two lines revised at one meeting are independent.
  class BudgetChanges
    Entry = Struct.new(:date, :subject, :area_total, :from, :to, :reason, :budget_update_id,
                       keyword_init: true) do
      def area_total? = area_total

      # A first figure on a line that had none, not a change.
      def first? = from.nil?
    end

    # Expects an area from the store, with its and its lines' forecasts preloaded.
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

    # By date, never by id: forecasts are re-dated on the edit page, so
    # insertion order is not the order things were agreed in.
    def self.ordered(forecasts)
      forecasts.sort_by { |forecast| [ forecast.date || forecast.created_at&.to_date || Date.new(0), forecast.id.to_i ] }
    end
    private_class_method :ordered
  end
end
