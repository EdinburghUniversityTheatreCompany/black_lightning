# Phase H MySQL cutover tooling. Run with the app still on the Airtable
# backend; re-runnable until the REIMBURSEMENTS_BACKEND flip (see
# docs/reimbursements/mysql-cutover-runbook.md for the runbook).
namespace :reimbursements do
  desc "Import all reimbursements data from Airtable into MySQL (idempotent; " \
       "YEAR_LABEL overrides the financial-year label; REMAP=1 additionally " \
       "rewrites owner_endorsements/batch_attempts to the numeric ids — ONLY " \
       "on the final pre-flip run, never during rehearsals)"
  task import_airtable: :environment do
    label = ENV["YEAR_LABEL"].presence || Reimbursements::AirtableImporter::DEFAULT_YEAR_LABEL
    Reimbursements::AirtableImporter.new(financial_year_label: label)
                                    .import!(remap_native_tables: ENV["REMAP"] == "1")
  end

  desc "Rollback companion to REMAP=1: rewrite owner_endorsements/batch_attempts " \
       "back to Airtable ids so the endorsement gate works on the Airtable backend again"
  task unremap_native_tables: :environment do
    Reimbursements::AirtableImporter.new.unremap!
  end
end
