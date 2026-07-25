module Reimbursements
  module Exports
    ##
    # BACS submission history, ONE ROW PER BATCH — the shape the History page
    # shows: when it went to EUSA, how many expenses it carried and what they
    # totalled, whether the EUSA draft was created, and where the receipts +
    # spreadsheet were backed up.
    #
    # Which expenses belong to which batch comes from the Expenses side (they
    # carry batch_id), so the per-batch figures here and the totals on the
    # History cards are computed from the same set. No bank details: a batch
    # summary has no payee columns, and the numbers EUSA pays from live only on
    # the BACS spreadsheet.
    class Batches < Base
      HEADERS = [ "Date sent", "Name", "Expenses", "Total", "Total ex VAT",
                  "EUSA draft", "SharePoint backup" ].freeze
      SHEET_NAME = "Batches".freeze
      SLUG = "batches".freeze

      private

      def row(batch)
        expenses = expenses_by_batch.fetch(batch.record_id, [])
        [
          iso_date(batch.date_sent), batch.name, expenses.size,
          total(expenses, :amount), total(expenses, :amount_excl_vat),
          batch.eusa_draft_created ? "Yes" : "No", batch.sharepoint_backup_url
        ]
      end

      def total(expenses, field)
        expenses.sum { |expense| expense.public_send(field) || 0 }
      end

      def expenses_by_batch
        @expenses_by_batch ||= store.expenses.select { |e| e.batch_id.present? }.group_by(&:batch_id)
      end
    end
  end
end
