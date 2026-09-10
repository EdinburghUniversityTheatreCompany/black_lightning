##
# The expense import's double-apply guard.
#
# The import wizard is stateless — apply re-parses the sheet from a hidden
# field rather than trusting the preview — so clicking apply twice would
# otherwise create every claim a second time. The budget import needs no such
# guard because it matches lines by name; a claim has no natural key, so the
# sheet has to carry one.
#
# import_key holds the reference the operator's own spreadsheet gave the claim,
# and the UNIQUE index is what actually enforces it: a pre-flight read can go
# stale between the preview and the apply, and between two operators. Same
# shape as source_message_id (email-in dedupe) and airtable_record_id (the
# retired importer's provenance), both already on this table.
#
# Nullable, with no backfill: every claim on file today came through the portal
# or by email, so it has no spreadsheet reference and never will. MySQL allows
# any number of NULLs in a unique index, so the constraint costs those rows
# nothing.
class AddImportKeyToReimbursementsExpenses < ActiveRecord::Migration[8.1]
  def change
    add_column :reimbursements_expenses, :import_key, :string
    add_index :reimbursements_expenses, :import_key, unique: true
  end
end
