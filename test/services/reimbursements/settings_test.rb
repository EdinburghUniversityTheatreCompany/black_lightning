require "test_helper"

module Reimbursements
  class SettingsTest < ActiveSupport::TestCase
    setup do
      @original_env = Rails.env.to_s
      @original_opt_in = ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"]
    end

    teardown do
      Rails.env = @original_env
      if @original_opt_in.nil?
        ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      else
        ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = @original_opt_in
      end
      ENV.delete("REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON")
    end

    test "azure_secret_expires_on parses a date and tolerates blanks" do
      assert_nil Settings.azure_secret_expires_on

      ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"] = "2028-07-09"
      assert_equal Date.new(2028, 7, 9), Settings.azure_secret_expires_on

      ENV["REIMBURSEMENTS_AZURE_SECRET_EXPIRES_ON"] = "not a date"
      assert_nil Settings.azure_secret_expires_on
    end

    test "outbound_enabled? follows REIMBURSEMENTS_ENABLE_OUTBOUND outside production" do
      assert_not Rails.env.production?

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = "1"
      assert Settings.outbound_enabled?, "opted in -> enabled"

      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = ""
      assert_not Settings.outbound_enabled?, "blank opt-in -> disabled"

      ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      assert_not Settings.outbound_enabled?, "absent opt-in -> disabled (dev/test default)"
    end

    # Nothing else in the suite runs the production branch: test_helper opts the
    # whole suite in. A blank opt-in must not switch production's outbound off.
    test "outbound_enabled? is true in production whatever the opt-in" do
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = ""

      Rails.env = "production"
      assert Rails.env.production?, "sanity: Rails.env really flipped"
      assert Settings.outbound_enabled?, "production ignores the opt-in entirely"
    end
  end
end
