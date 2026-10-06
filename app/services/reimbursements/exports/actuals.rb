module Reimbursements
  module Exports
    ##
    # The imported EUSA Actuals ledger. A row's debit/credit pair collapses to
    # Type + Amount, and the linked expense and budget resolve to the expense's
    # auto-number and the budget's name, as the Actuals browser shows them.
    #
    # Amount is SIGNED (debit positive, credit negative), so a SUM of the column
    # is net spend and an offsetting pair cancels. Status ("Offset") lets those
    # pairs be filtered out.
    class Actuals < Base
      HEADERS = [ "Date", "Type", "Description", "Amount", "Budget",
                  "Linked expense", "Period", "Status", "Cost centre", "Area" ].freeze
      SHEET_NAME = "Actuals".freeze
      SLUG = "actuals".freeze

      private

      def row(actual)
        debit = actual.debit&.positive?
        credit = actual.credit
        budget = budget_by_id[actual.linked_budget_ids.first]
        expense = expense_by_id[actual.linked_expense_ids.first]
        [
          iso_date(actual.date),
          debit ? "Debit" : (credit&.positive? ? "Credit" : ""),
          actual.narrative,
          # Spend positive, income negative; a blank stays blank, never "-0.0".
          debit ? actual.debit : (credit&.positive? ? -credit : credit),
          # A split row has no budget_id: name each share as the ledger page does
          # ("Show A £2,500.00; Show B £1,500.00").
          actual.apportioned? ? actual.allocation_summary : budget&.name,
          expense&.auto_number,
          actual.period,
          actual.reconciliation_status.presence&.capitalize,
          cost_centre_name(actual.cost_centre_id),
          # The budget booked directly, else the linked expense's, both off the
          # preloaded map. Blank for a split row: its shares can sit in
          # different areas.
          (budget || budget_by_id[expense&.budget_record_id])&.area&.name
        ]
      end
    end
  end
end
