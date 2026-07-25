module Reimbursements
  module Exports
    ##
    # The imported EUSA Actuals ledger. A row's debit/credit pair collapses to a
    # Type + Amount, and the linked expense/budget references resolve to the
    # expense's visible auto-number and the budget's name, exactly as the
    # Actuals browser renders them.
    class Actuals < Base
      HEADERS = [ "Date", "Type", "Description", "Amount", "Budget",
                  "Linked expense", "Period" ].freeze
      SHEET_NAME = "Actuals".freeze
      SLUG = "actuals".freeze

      private

      def row(actual)
        debit = actual.debit&.positive?
        [
          iso_date(actual.date),
          debit ? "Debit" : (actual.credit&.positive? ? "Credit" : ""),
          actual.narrative,
          debit ? actual.debit : actual.credit,
          budget_by_id[actual.linked_budget_ids.first]&.name,
          expense_by_id[actual.linked_expense_ids.first]&.auto_number,
          actual.period
        ]
      end
    end
  end
end
