module Reimbursements
  module Exports
    ##
    # BACS submission history, one row per batch, as the History page shows it:
    # when it went to EUSA, its expense count and totals, whether the EUSA draft
    # was created, and the backup link.
    #
    # Per-batch figures come from the expenses carrying the batch_id, the same
    # set as the History cards. No bank details: those live only on the BACS
    # spreadsheet.
    #
    # DELIBERATELY no "Area" column: a batch spans several claims and so several
    # shows, so one cell would be a lie rather than a blank. Not an oversight to
    # finish.
    class Batches < Base
      HEADERS = [ "Date sent", "Name", "Expenses", "Total", "Total ex VAT",
                  "EUSA draft", "SharePoint backup", "Cost centre" ].freeze
      SHEET_NAME = "Batches".freeze
      SLUG = "batches".freeze

      private

      def row(batch)
        expenses = expenses_by_batch.fetch(batch.record_id, [])
        [
          iso_date(batch.date_sent), batch.name, expenses.size,
          total(expenses, :amount), total(expenses, :amount_excl_vat),
          batch.eusa_draft_created ? "Yes" : "No", batch.sharepoint_backup_url,
          batch_cost_centre_name(expenses)
        ]
      end

      # A batch has no cost-centre column; it takes its centre from its expenses.
      # Blank rather than guessing the default centre for an empty or mixed
      # batch: an export is read as a record, not a reminder.
      def batch_cost_centre_name(expenses)
        ids = expenses.filter_map(&:cost_centre_id).uniq
        ids.one? ? cost_centre_name(ids.first) : nil
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
