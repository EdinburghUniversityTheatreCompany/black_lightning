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
  end
end
