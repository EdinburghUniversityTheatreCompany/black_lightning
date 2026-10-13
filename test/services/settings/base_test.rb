require "test_helper"

class Settings::BaseTest < ActiveSupport::TestCase
  # A throwaway module per test, so nothing here depends on how the real
  # Settings modules happen to be configured.
  def build_settings(&block)
    Module.new do
      extend ::Settings::Base
      instance_eval(&block)
    end
  end

  setup do
    @env_keys = []
  end

  teardown do
    @env_keys.each { |key| ENV.delete(key) }
  end

  def set_env(key, value)
    @env_keys << key
    ENV[key] = value
  end

  def widget_settings(*keys)
    build_settings do
      reads_from env: "WIDGET", credentials: :widget
      setting(*keys)
    end
  end

  test "a setting reads its ENV variable" do
    settings = widget_settings(:api_token)
    set_env("WIDGET_API_TOKEN", "from-env")

    assert_equal "from-env", settings.api_token
  end

  test "a blank ENV variable falls through rather than winning" do
    settings = widget_settings(:api_token)
    set_env("WIDGET_API_TOKEN", "")

    assert_nil settings.api_token
  end

  test "an unset setting is nil" do
    settings = widget_settings(:api_token)

    assert_nil settings.api_token
  end

  # No mocking library: a source answering from memory stands in for ENV and credentials.
  FakeSource = Struct.new(:env_result, :credentials_result) do
    def env_value(_key) = env_result
    def credentials_value(_key) = credentials_result
  end

  def settings_reading(source)
    build_settings { setting :api_token }.tap { |settings| settings.instance_variable_set(:@settings_source, source) }
  end

  test "ENV beats credentials, and credentials answer when ENV does not" do
    assert_equal "from-env", settings_reading(FakeSource.new("from-env", "from-creds")).api_token
    assert_equal "from-creds", settings_reading(FakeSource.new(nil, "from-creds")).api_token
  end

  test "settings_present? defaults to every declared key and can be asked about a subset" do
    settings = widget_settings(:one, :two)
    set_env("WIDGET_ONE", "1")

    assert settings.settings_present?(:one)
    assert_not settings.settings_present?(:two)
    assert_not settings.settings_present?

    set_env("WIDGET_TWO", "2")
    assert settings.settings_present?
  end
end
