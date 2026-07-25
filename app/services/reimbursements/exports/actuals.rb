module Reimbursements
  module Exports
    ##
    # The imported EUSA Actuals ledger. A row's debit/credit pair collapses to a
    # Type + Amount, and the linked expense/budget references resolve to the
    # expense's visible auto-number and the budget's name, exactly as the
    # Actuals browser renders them.
    #
    # Amount is SIGNED: a debit (spend) is positive, a credit (income, a refund,
    # an accrual reversal) is negative. Finance re-imports these files and sums
    # the column, and an unsigned amount made that sum meaningless — it added
    # income to spend, and an offsetting pair contributed twice its value instead
    # of the zero it really is. With signs, a naive SUM of Amount is net spend
    # for whatever rows the export contains, and a cross-linked pair cancels
    # itself out. Status names the reconciliation state ("Offset") so the pairs
    # that net to zero can also be filtered out entirely.
    class Actuals < Base
      HEADERS = [ "Date", "Type", "Description", "Amount", "Budget",
                  "Linked expense", "Period", "Status" ].freeze
      SHEET_NAME = "Actuals".freeze
      SLUG = "actuals".freeze

      private

      def row(actual)
        debit = actual.debit&.positive?
        [
          iso_date(actual.date),
          debit ? "Debit" : (actual.credit&.positive? ? "Credit" : ""),
          actual.narrative,
          signed_amount(actual, debit),
          budget_by_id[actual.linked_budget_ids.first]&.name,
          expense_by_id[actual.linked_expense_ids.first]&.auto_number,
          actual.period,
          actual.reconciliation_status.presence&.capitalize
        ]
      end

      # Spend positive, income negative. A row with neither (both columns blank
      # or zero) stays whatever it was, so a blank cell never becomes "-0.0".
      def signed_amount(actual, debit)
        return actual.debit if debit
        return nil if actual.credit.nil?

        actual.credit.positive? ? -actual.credit : actual.credit
      end
    end
  end
end
