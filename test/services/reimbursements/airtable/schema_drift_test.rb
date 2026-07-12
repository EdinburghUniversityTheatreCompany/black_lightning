require "test_helper"

module Reimbursements
  module Airtable
    # Schema-drift guard for the Airtable field mapping.
    #
    # Config#fid returns nil for an unknown field (so a lagging credentials set
    # degrades to blank data instead of 500-ing the page). That safety comes at a
    # cost: a renamed or removed Airtable column now fails silently. These tests
    # make that failure loud by asserting every field the app code resolves
    # through fid (ReimbursementsTestHelpers::EXPECTED_AIRTABLE_FIELDS — the
    # source of truth) actually exists in the config.
    class SchemaDriftTest < ActiveSupport::TestCase
      include ReimbursementsTestHelpers

      test "every field the app needs resolves in the canonical Airtable schema" do
        assert_airtable_fields_resolve(reimbursements_test_config)
      end

      test "every field the app needs resolves in the real credentials, when configured" do
        raw = Rails.application.credentials.reimbursements_airtable
        skip "reimbursements_airtable credentials not configured in this environment" if raw.blank?

        assert_airtable_fields_resolve(Config.from_credentials)
      end

      # Keeps the expected-fields list honest: if a new fid(:table, :field) call
      # is added to the code but not to EXPECTED_AIRTABLE_FIELDS, the guard above
      # would silently stop covering it. Scan the source for every literal fid
      # pair and require each to be listed.
      test "expected-fields list covers every literal fid() call in the code" do
        pattern = /fid\(:([a-z_]+),\s*:([a-z_0-9]+)\)/
        sources = Dir[Rails.root.join("app/services/reimbursements/**/*.rb")]
        referenced = sources.flat_map do |path|
          File.read(path).scan(pattern).map { |table, field| [ table.to_sym, field.to_sym ] }
        end.uniq

        expected_pairs = EXPECTED_AIRTABLE_FIELDS.flat_map do |table, fields|
          fields.map { |field| [ table, field ] }
        end

        unlisted = referenced - expected_pairs
        assert_empty unlisted,
                     "These fid(:table, :field) calls exist in the code but aren't in " \
                     "EXPECTED_AIRTABLE_FIELDS — add them so the schema-drift guard covers " \
                     "them: #{unlisted.map { |t, f| "#{t}.#{f}" }.join(', ')}"
      end
    end
  end
end
