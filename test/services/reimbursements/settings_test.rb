require "test_helper"

module Reimbursements
  class SettingsTest < ActiveSupport::TestCase
    teardown do
      ENV.delete("REIMBURSEMENTS_GEMINI_API_KEY")
      ENV.delete("REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON")
    end

    test "env var overrides credentials" do
      ENV["REIMBURSEMENTS_GEMINI_API_KEY"] = "env-key"
      assert_equal "env-key", Settings.gemini_api_key
    end

    test "falls back to credentials (absent in test env)" do
      assert_nil Settings.gemini_api_key
      assert_nil Settings.alert_email
    end

    test "azure_secret_expires_on parses a date and tolerates blanks" do
      assert_nil Settings.azure_secret_expires_on

      ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"] = "2028-07-09"
      assert_equal Date.new(2028, 7, 9), Settings.azure_secret_expires_on

      ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"] = "not a date"
      assert_nil Settings.azure_secret_expires_on
    end

    # In the test env (non-production), outbound is gated on the explicit
    # REIMBURSEMENTS_ENABLE_OUTBOUND opt-in.
    test "outbound_enabled? follows REIMBURSEMENTS_ENABLE_OUTBOUND outside production" do
      assert_not Rails.env.production?
      original = ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"]

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = "1"
      assert Settings.outbound_enabled?, "opted in -> enabled"

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = ""
      assert_not Settings.outbound_enabled?, "blank opt-in -> disabled"

      ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      assert_not Settings.outbound_enabled?, "absent opt-in -> disabled (dev/test default)"
    ensure
      if original.nil?
        ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      else
        ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original
      end
    end

    # The OTHER half of the gate: production must send unconditionally. Nothing
    # else in the suite runs this branch (test_helper opts the whole suite in via
    # REIMBURSEMENTS_ENABLE_OUTBOUND), so deleting `return true if
    # Rails.env.production?` would leave production silently refusing to send
    # every rejection/payment email, every mailbox reply and every EUSA BACS
    # draft — with create_draft handing back a fake "suppressed-…" id. Rails.env
    # is assignable, so no mocking library is needed.
    test "outbound_enabled? is true in production with no opt-in set at all" do
      original_env = Rails.env.to_s
      original_opt_in = ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"]
      ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")

      Rails.env = "production"
      assert Rails.env.production?, "sanity: Rails.env really flipped"
      assert Settings.outbound_enabled?,
             "production must send even with REIMBURSEMENTS_ENABLE_OUTBOUND unset"
    ensure
      Rails.env = original_env
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original_opt_in unless original_opt_in.nil?
    end

    # The opt-in is irrelevant in production: an operator who explicitly set it
    # to blank must not be able to switch production's outbound off by accident.
    test "outbound_enabled? ignores a blank opt-in in production" do
      original_env = Rails.env.to_s
      original_opt_in = ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"]
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = ""

      Rails.env = "production"
      assert Settings.outbound_enabled?, "production ignores the opt-in entirely"
    ensure
      Rails.env = original_env
      if original_opt_in.nil?
        ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      else
        ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original_opt_in
      end
    end
  end
end
