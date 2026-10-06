module Reimbursements
  module Exports
    ##
    # Every logged revision of a plan, one row per forecast: a budget line's
    # allocation or an area's agreed total, with date, figure, reason and the
    # batched revision it belonged to.
    #
    # A forecast belongs to exactly ONE of a budget or an area (model validation
    # plus a MySQL CHECK), so "Revises" names whichever and "Level" says which.
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
          # display_name for a line (it names its area too), plain name for an area.
          forecast.budget ? owner.display_name : owner.name,
          forecast.amount,
          forecast.reason,
          # A standalone forecast has no batched revision: empty, not "-".
          forecast.budget_update && update_label(forecast.budget_update),
          forecast.budget_update&.created_by&.full_name,
          owner.financial_year&.label,
          cost_centre_name(owner.cost_centre_id)
        ]
      end

      def update_label(budget_update)
        [ budget_update.effective_date&.iso8601, budget_update.note.presence ].compact.join(" · ")
      end
    end
  end
end
