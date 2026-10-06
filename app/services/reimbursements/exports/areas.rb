module Reimbursements
  module Exports
    ##
    # The shows and committees a year's budget lines hang off, one row per area:
    # agreed total, what it is a total OF, how much is allocated to lines, owners.
    #
    # A blank agreed total is an EMPTY cell, never 0: a plan of exactly £0 is
    # unset (PlannedAmount), and a zero would read as a show that agreed to
    # spend nothing.
    class Areas < Base
      HEADERS = [ "Area", "Agreed total", "Total covers", "Allocated to lines",
                  "Not yet allocated", "Lines", "Owners", "Active", "Financial year",
                  "Cost centre" ].freeze
      SHEET_NAME = "Areas".freeze
      SLUG = "areas".freeze

      private

      def row(area)
        [
          area.name,
          area.no_budget_set? ? nil : area.projected_amount,
          # The words the form and every card use: a spend cap or a net allowance.
          area.basis_qualifier,
          area.allocated,
          area.unallocated,
          area.budgets.size,
          area.owners.map(&:name).sort.join(", ").presence,
          area.active ? "Yes" : "No",
          area.financial_year&.label,
          cost_centre_name(area.cost_centre_id)
        ]
      end
    end
  end
end
