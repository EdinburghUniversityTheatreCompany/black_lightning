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
        [
          iso_date(actual.date),
          debit ? "Debit" : (actual.credit&.positive? ? "Credit" : ""),
          actual.narrative,
          signed_amount(actual, debit),
          budget_cell(actual),
          expense_by_id[actual.linked_expense_ids.first]&.auto_number,
          actual.period,
          actual.reconciliation_status.presence&.capitalize,
          cost_centre_name(actual.cost_centre_id), area_name(actual)
        ]
      end

      # A split row has no budget_id, so name each share as the ledger page does
      # ("Show A £2,500.00; Show B £1,500.00") rather than leave the cell blank.
      def budget_cell(actual)
        return actual.allocation_summary if actual.apportioned?

        budget_by_id[actual.linked_budget_ids.first]&.name
      end

      # Spend positive, income negative; a blank stays blank, never "-0.0".
      def signed_amount(actual, debit)
        return actual.debit if debit
        return nil if actual.credit.nil?

        actual.credit.positive? ? -actual.credit : actual.credit
      end

      # The budget booked directly, or else the one on the linked expense. Both
      # through budget_by_id so the area comes off the same preloaded object.
      def linked_budget(actual)
        budget_by_id[actual.linked_budget_ids.first] ||
          budget_by_id[expense_by_id[actual.linked_expense_ids.first]&.budget_record_id]
      end

      # Blank for a SPLIT row: its shares can sit in different areas, and one
      # cell would be a lie rather than a blank.
      def area_name(actual)
        linked_budget(actual)&.area&.name
      end
    end
  end
end
