namespace :reimbursements do
  # Schema-drift guard for the Airtable field mapping, runnable against real
  # credentials (e.g. RAILS_ENV=production bin/rails reimbursements:verify_airtable_schema)
  # after editing the Airtable base or rotating the credentials.
  #
  # Config#fid returns nil for an unknown field, so a renamed/removed column now
  # degrades to blank data instead of raising. This asserts every field the app
  # code needs (ReimbursementsTestHelpers::EXPECTED_AIRTABLE_FIELDS — the same
  # source of truth the schema_drift_test uses) still resolves, and aborts with
  # the full list of gaps if not. Mirrors bedlam-bacs' field-id sanity check.
  desc "Verify every Airtable field id the app needs resolves in the credentials"
  task verify_airtable_schema: :environment do
    require Rails.root.join("test/support/reimbursements_test_helpers").to_s

    config = Reimbursements::Airtable::Config.from_credentials
    missing = ReimbursementsTestHelpers::EXPECTED_AIRTABLE_FIELDS.flat_map do |table, fields|
      fields.filter_map { |field| "#{table}.#{field}" if config.fid(table, field).nil? }
    end

    if missing.any?
      abort "Airtable schema drift: #{missing.size} field(s) the app needs did not " \
            "resolve in the credentials (renamed/removed column, or credentials lag " \
            "the code):\n  #{missing.join("\n  ")}"
    end

    total = ReimbursementsTestHelpers::EXPECTED_AIRTABLE_FIELDS.sum { |_, fields| fields.size }
    puts "OK: all #{total} expected Airtable field ids resolve in the credentials."
  end
end
