require "csv"

module Reimbursements
  ##
  # One exporter per resource. Each defines its headers and per-record row once,
  # and that one definition drives both the per-view "Download CSV" and the
  # matching workbook sheet (ExportsController), so the two cannot disagree
  # about a column.
  module Exports
    ##
    # Shared plumbing: row building, the formula-injection guard, the CSV
    # filename and the record lookups more than one exporter needs.
    #
    # Subclasses define HEADERS, SHEET_NAME, SLUG and a private #row(record).
    # Rows come from whatever collection the caller passes: a controller its
    # full filtered set (pagination is display-only), the workbook the scoped
    # readers in Workbook::SHEETS.
    #
    # Conventions every exporter follows:
    #
    # * Amounts stay numeric (no "£", no thousands separators) so they sum and
    #   sort in Excel.
    # * Dates are ISO 8601; a blank date is an EMPTY cell, not the on-screen "-".
    # * Every text cell goes through CellSanitizer.
    class Base
      # +checker+ is the modulus checker (a fake in tests), for the exporters
      # that give a bank-details verdict.
      def initialize(store:, checker: nil)
        @store = store
        @checker = checker
      end

      def headers = self.class::HEADERS

      # "reimbursements-expenses-2026-05-13.csv"
      def filename = "reimbursements-#{self.class::SLUG}-#{Date.current.iso8601}.csv"

      def to_csv(collection)
        CSV.generate do |csv|
          csv << headers
          rows(collection).each { |row| csv << row }
        end
      end

      # Sheet names are fixed, never date-templated: Excel caps them at 31
      # characters and a saved formula referencing a sheet keeps working.
      def add_sheet(workbook, collection)
        workbook.add_worksheet(name: self.class::SHEET_NAME) do |sheet|
          sheet.add_row(headers, types: cell_types(headers))
          rows(collection).each { |row| sheet.add_row(row, types: cell_types(row)) }
        end
      end

      private

      attr_reader :store

      # Defaults lazily, so an exporter that never asks does not load the Pay.UK rules.
      def checker
        @checker ||= ModulusCheck.default_checker
      end

      def rows(collection)
        collection.map { |record| row(record).map { |value| CellSanitizer.cell(value) } }
      end

      # Keeps every String cell literal text (nil means "infer"). Axlsx would
      # coerce a numeric-looking one: nominal code "041000" to 41000, EUSA
      # period "03" to 3. A quantity is always a Numeric and a String an
      # identifier or label, so no per-column configuration is needed.
      def cell_types(row)
        row.map { |value| value.is_a?(String) ? :string : nil }
      end

      # ISO 8601, or nil so the cell comes out empty.
      def iso_date(value)
        value&.to_date&.iso8601
      end

      # {record_id => record} lookups, memoized per exporter instance.
      def budget_by_id
        @budget_by_id ||= store.budgets.index_by(&:record_id)
      end

      def expense_by_id
        @expense_by_id ||= store.expenses.index_by(&:record_id)
      end

      # Every exporter that can name a centre carries the column: an export is
      # where two centres' figures are most easily added together by hand.
      # Blank (not "-") when nothing places the row.
      def cost_centre_name(cost_centre_id) = cost_centre_by_id[cost_centre_id]&.name

      def cost_centre_by_id
        @cost_centre_by_id ||= store.cost_centres.index_by(&:id)
      end
    end
  end
end
