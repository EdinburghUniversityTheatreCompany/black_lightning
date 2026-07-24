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
    # REIMBURSEMENTS_ENABLE_OUTBOUND opt-in. The production branch (always true)
    # can't be exercised without stubbing Rails.env, and this suite has no
    # mocking library — so cover the seam that actually guards dev/test safety.
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
  end
end
