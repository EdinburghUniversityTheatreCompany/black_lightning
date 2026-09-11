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
    #
    # DELIBERATELY NO "Area" column, unlike Budgets/Expenses/Actuals: a batch
    # spans several claims and so several shows, making a single Area cell a lie
    # rather than a blank. Exports::People carries no Cost centre for the same
    # reason. Not an oversight to "finish".
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

      # A Batch carries no cost-centre column: it takes its centre from the
      # expenses it holds, which is exact now that a batch is built for one
      # centre over that centre'''s claims only. A batch holding nothing, or only
      # unplaced claims, leaves the cell empty rather than guessing at the
      # default centre — an export is read as a record, not as a reminder.
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
