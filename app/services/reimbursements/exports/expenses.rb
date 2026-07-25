module Reimbursements
  module Exports
    ##
    # Expenses as finance sees them on the "Expenses" table (ExpenseEdits) and
    # the Review queue: the EFFECTIVE payee (the money path, so an Invoice
    # override shows the third party actually being paid), both amount figures,
    # and the same needs-attention reasons the on-screen rows carry.
    #
    # Bank details are deliberately NOT here — the effective sort code and
    # account number exist only on the BACS spreadsheet that goes to EUSA.
    class Expenses < Base
      HEADERS = [ "#", "Status", "Payee", "Budget", "Amount", "Amount ex VAT",
                  "Description", "Payment reference", "Submitted", "Needs attention" ].freeze
      SHEET_NAME = "Expenses".freeze
      SLUG = "expenses".freeze

      private

      def row(expense)
        [
          expense.auto_number, expense.status, expense.effective_payee_name,
          expense.budget&.name, expense.amount, expense.amount_excl_vat,
          expense.description, expense.payment_reference,
          iso_date(expense.submitted_at), attention_reasons(expense).join("; ")
        ]
      end

      # Match the on-screen table: no attention reasons on non-actionable
      # (Submitted/Paid/Rejected) rows, so the export and the table can't
      # disagree about what still needs chasing.
      def attention_reasons(expense)
        return [] unless ReviewSupport.attention_actionable?(expense)

        ReviewSupport.needs_attention_reasons(expense, budget_by_id, checker)
      end
    end
  end
end
