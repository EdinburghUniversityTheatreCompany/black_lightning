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
                  "Linked expense", "Period", "Status", "Cost centre", "Area" ].freeze
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
          actual.reconciliation_status.presence&.capitalize,
          cost_centre_name(actual.cost_centre_id), area_name(actual)
        ]
      end

      # Spend positive, income negative. A row with neither (both columns blank
      # or zero) stays whatever it was, so a blank cell never becomes "-0.0".
      def signed_amount(actual, debit)
        return actual.debit if debit
        return nil if actual.credit.nil?

        actual.credit.positive? ? -actual.credit : actual.credit
      end

      # The linked budget however the row reaches one: booked directly
      # (budget_id, what the "Budget" column above reads) or reconciled to an
      # expense whose own budget resolves it — which "Budget" does not surface,
      # but the area is worth resolving anyway. Through budget_by_id both times,
      # never expense.budget, so the area comes off the same preloaded
      # (area: :owners) object either way; both maps are already built for
      # every row by the lookups above.
      def linked_budget(actual)
        budget_by_id[actual.linked_budget_ids.first] ||
          budget_by_id[expense_by_id[actual.linked_expense_ids.first]&.budget_record_id]
      end

      def area_name(actual)
        linked_budget(actual)&.area&.name
      end
    end
  end
end
