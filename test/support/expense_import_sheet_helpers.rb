# Sheets for the expense import's model, controller and system tests. Rows are built
# in ExpenseImport::FIELDS order, so adding a column cannot shift every later cell.
module ExpenseImportSheetHelpers
  # One well-formed line, with the fields a test cares about overridden.
  def expense_import_row(**overrides)
    unknown = overrides.keys - ::Reimbursements::ExpenseImport::FIELDS.keys
    raise ArgumentError, "unknown expense import fields: #{unknown.inspect}" if unknown.any?

    cells = { reference: "OLD-1", status: ::Reimbursements::Status::PAID,
              payee_email: "alice@example.com", budget: "Props", amount: "120.00",
              amount_excl_vat: "100.00", description: "Fake blood",
              payment_reference: "PROPS ALICE" }.merge(overrides)
    ::Reimbursements::ExpenseImport::FIELDS.each_key.map { |field| cells.fetch(field, "") }.join("\t")
  end

  def expense_import_sheet(*rows)
    ([ ::Reimbursements::ExpenseImport::TSV_HEADERS.join("\t") ] + rows).join("\n")
  end
end
