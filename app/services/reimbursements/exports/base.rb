require "csv"

module Reimbursements
  ##
  # One exporter per resource (Expenses, Actuals, Budgets, People, Batches),
  # each defining its column headers and its per-record row exactly once. That
  # single definition drives BOTH the per-view "Download CSV" link and the
  # matching sheet in the combined workbook (ExportsController), so a column
  # can never say one thing in the CSV and another in the xlsx.
  module Exports
    ##
    # Shared plumbing: headers, row building, the formula-injection guard, the
    # download filename, and the record lookups more than one exporter needs.
    #
    # Subclasses define HEADERS, SHEET_NAME, SLUG and a private #row(record).
    # Rows are built from whatever collection the caller passes in — a
    # controller hands over its FULL filtered set (pagination is display-only),
    # the workbook hands over everything the store has.
    #
    # Conventions every exporter follows, so the output is spreadsheet-ready:
    #
    # * Amounts stay numeric (no "£" prefix, no thousands separators) so they
    #   sum and sort in Excel.
    # * Dates are ISO 8601 strings; a blank date is an EMPTY cell, not the "-"
    #   placeholder the on-screen tables use.
    # * Every text cell goes through CellSanitizer, closing the formula-
    #   injection hole in submitter-controlled text (description, payee name).
    class Base
      # +checker+ is the modulus checker (a fake in tests); only the exporters
      # that surface a bank-detail verdict need it.
      def initialize(store:, checker: nil)
        @store = store
        @checker = checker
      end

      def headers = self.class::HEADERS

      def sheet_name = self.class::SHEET_NAME

      # "reimbursements-expenses-2026-05-13.csv" — the resource plus the day it
      # was pulled, so a folder of exports stays self-describing.
      def filename(date: Date.current)
        "reimbursements-#{self.class::SLUG}-#{date.iso8601}.csv"
      end

      def to_csv(collection)
        CSV.generate do |csv|
          csv << headers
          rows(collection).each { |row| csv << row }
        end
      end

      # Append this resource as one worksheet of +workbook+ (an Axlsx workbook).
      # Sheet names are fixed (never templated with a date) so they stay inside
      # Excel's 31-character cap and a saved formula referencing a sheet keeps
      # working across exports.
      def add_sheet(workbook, collection, name: sheet_name)
        workbook.add_worksheet(name: name) do |sheet|
          sheet.add_row(headers, types: cell_types(headers))
          rows(collection).each { |row| sheet.add_row(row, types: cell_types(row)) }
        end
      end

      private

      attr_reader :store

      # The modulus checker People/Expenses need for their bank-details verdict.
      # Optional at construction (most exporters never touch it, and the finance
      # controllers inject the real one or a fake) but never nil when READ,
      # since Workbook.new(store:) legitimately passes none. Resolved lazily, so
      # an exporter that doesn't need a verdict never loads the Pay.UK rule
      # files.
      def checker
        @checker ||= ModulusCheck.default_checker
      end

      def rows(collection)
        collection.map { |record| row(record).map { |value| CellSanitizer.cell(value) } }
      end

      def row(_record)
        raise NotImplementedError, "#{self.class} must define a private #row(record)"
      end

      # Force every String cell to stay literal text in the xlsx; let Axlsx
      # infer the rest (nil means "infer").
      #
      # Axlsx types a cell from its value, and a numeric-LOOKING string becomes
      # a number: nominal code "041000" would arrive as 41000 and EUSA period
      # "03" as 3, silently corrupting the identifiers finance reconciles on.
      # The exporters already draw the line for us — a quantity is a Numeric, a
      # String is always an identifier or a label — so this needs no per-column
      # configuration. It is the same reason BacsXlsx forces text format on the
      # sort code, account number and nominal code.
      def cell_types(row)
        row.map { |value| value.is_a?(String) ? :string : nil }
      end

      # ISO 8601, or nil so the cell comes out empty. Accepts a Date or a Time.
      def iso_date(value)
        value&.to_date&.iso8601
      end

      # Shared {record_id => record} lookups. Memoized per exporter instance,
      # over the store's already-loaded lists, so resolving a linked budget or
      # expense costs no extra queries however many rows are exported.
      def budget_by_id
        @budget_by_id ||= store.budgets.index_by(&:record_id)
      end

      def expense_by_id
        @expense_by_id ||= store.expenses.index_by(&:record_id)
      end
    end
  end
end
