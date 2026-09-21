module Reimbursements
  module Exports
    ##
    # The shows and committees a year's budget lines hang off, ONE ROW PER
    # AREA: its agreed total, what that total is a total OF, how much of it is
    # allocated to lines, and who owns it.
    #
    # Agreed totals, bases, owners and allocation could not be exported in any
    # format at all — they existed only on the areas index and each area's own
    # page — which for a committee report is the one table anybody asks for.
    #
    # A blank agreed total is an EMPTY cell, never 0: a plan of exactly £0 is a
    # figure nobody filled in (PlannedAmount), and a zero here would read as a
    # show that agreed to spend nothing.
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
          # The words the form and every card use, so a reader who has seen one
          # recognises the other: a show gets a spend cap, a committee a net
          # allowance.
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
