# Phase H MySQL cutover tooling. Run with the app still on the Airtable
# backend; re-runnable until the REIMBURSEMENTS_BACKEND flip (see
# docs/reimbursements/mysql-migration-and-roadmap.md for the runbook).
namespace :reimbursements do
  desc "Import all reimbursements data from Airtable into MySQL (idempotent; " \
       "YEAR_LABEL overrides the financial-year label)"
  task import_airtable: :environment do
    label = ENV["YEAR_LABEL"].presence || Reimbursements::AirtableImporter::DEFAULT_YEAR_LABEL
    Reimbursements::AirtableImporter.new(financial_year_label: label).import!
  end
end
