module Reimbursements
  module Exports
    ##
    # Expenses as finance sees them on the Expenses table and Review queue: the
    # EFFECTIVE payee (so an Invoice override shows the third party being paid),
    # both amounts, and the on-screen needs-attention reasons.
    #
    # Bank details are deliberately NOT here; they live only on the BACS
    # spreadsheet that goes to EUSA.
    class Expenses < Base
      HEADERS = [ "#", "Status", "Payee", "Budget", "Amount", "Amount ex VAT",
                  "Description", "Payment reference", "Submitted", "Needs attention",
                  "Cost centre", "Area" ].freeze
      SHEET_NAME = "Expenses".freeze
      SLUG = "expenses".freeze

      private

      def row(expense)
        budget = budget_by_id[expense.budget_record_id]
        [
          expense.auto_number, expense.status, expense.effective_payee_name,
          # Bare budget name: the sheet has its own Area column.
          budget&.name, expense.amount, expense.amount_excl_vat,
          expense.description, expense.payment_reference,
          iso_date(expense.submitted_at), attention_reasons(expense).join("; "),
          cost_centre_name(expense.cost_centre_id), budget&.area&.name
        ]
      end

      # Actionable rows only, to match the on-screen table.
      def attention_reasons(expense)
        return [] unless ReviewSupport.attention_actionable?(expense)

        ReviewSupport.needs_attention_reasons(expense, budget_by_id, checker)
      end
    end
  end
end
