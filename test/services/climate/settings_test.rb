require "test_helper"

class Climate::SettingsTest < ActiveSupport::TestCase
  setup { @original = ENV.fetch("CLIMATE_GOVEE_API_KEY", nil) }

  teardown do
    if @original.nil?
      ENV.delete("CLIMATE_GOVEE_API_KEY")
    else
      ENV["CLIMATE_GOVEE_API_KEY"] = @original
    end
  end

  test "reads the govee key from the environment" do
    ENV["CLIMATE_GOVEE_API_KEY"] = "from-env"

    assert_equal "from-env", Climate::Settings.govee_api_key
  end

  test "govee_configured? is false when nothing is set" do
    ENV.delete("CLIMATE_GOVEE_API_KEY")

    # Nothing in the test credentials either, so this is the unconfigured case
    # the poll job treats as "stay quiet" rather than "fail".
    assert_not Climate::Settings.govee_configured?
  end

  test "govee_configured? is true once a key is present" do
    ENV["CLIMATE_GOVEE_API_KEY"] = "from-env"

    assert_predicate Climate::Settings, :govee_configured?
  end

  test "an empty environment variable counts as unset rather than as a blank key" do
    # Otherwise an exported-but-empty var in a shell would make the job think it
    # was configured and fail every poll with a 401.
    ENV["CLIMATE_GOVEE_API_KEY"] = ""

    assert_not Climate::Settings.govee_configured?
  end
end
