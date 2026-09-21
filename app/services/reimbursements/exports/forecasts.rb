module Reimbursements
  module Exports
    ##
    # Every logged revision of a plan, ONE ROW PER FORECAST — a budget line's
    # allocation or an area's agreed total, with the date, the figure, the
    # reason and the batched revision it belonged to.
    #
    # Forecast history could not be exported in any format. It is the answer to
    # "why is this line's plan £950 when the committee agreed £700", and it
    # lived only inside each budget's own edit page, one line at a time.
    #
    # A forecast belongs to exactly ONE of a budget or an area (model
    # validation plus a MySQL CHECK), so the "Revises" column names whichever
    # it is and "Level" says which kind, rather than leaving a reader to infer
    # it from a blank.
    class Forecasts < Base
      HEADERS = [ "Date", "Level", "Revises", "Amount", "Reason",
                  "Part of update", "Logged by", "Financial year", "Cost centre" ].freeze
      SHEET_NAME = "Forecast revisions".freeze
      SLUG = "forecast-revisions".freeze

      private

      def row(forecast)
        owner = forecast.budget || forecast.area
        [
          iso_date(forecast.date),
          forecast.budget_id ? "Budget line" : "Area total",
          # display_name for a line (it names its area too, which is the whole
          # point of that composition) and the plain name for an area.
          forecast.budget ? forecast.budget.display_name : forecast.area&.name,
          forecast.amount,
          forecast.reason,
          # A standalone per-budget entry belongs to no batched revision, and an
          # empty cell says that more honestly than a repeated "-".
          forecast.budget_update && update_label(forecast.budget_update),
          forecast.budget_update&.created_by&.full_name,
          owner&.financial_year&.label,
          cost_centre_name(owner&.cost_centre_id)
        ]
      end

      # The revision a forecast came in under, named the way the log names it:
      # its effective date, plus its note where there is one.
      def update_label(budget_update)
        [ budget_update.effective_date&.iso8601, budget_update.note.presence ].compact.join(" — ")
      end
    end
  end
end
