require "test_helper"

class Settings::BaseTest < ActiveSupport::TestCase
  # A throwaway module per test, so nothing here depends on how the four real
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

  test "a setting reads its ENV variable" do
    settings = build_settings do
      reads_from env: "WIDGET", credentials: :widget
      setting :api_token
    end
    set_env("WIDGET_API_TOKEN", "from-env")

    assert_equal "from-env", settings.api_token
  end

  test "a blank ENV variable falls through rather than winning" do
    settings = build_settings do
      reads_from env: "WIDGET", credentials: :widget
      setting :api_token
    end
    set_env("WIDGET_API_TOKEN", "")

    assert_nil settings.api_token
  end

  test "an unset setting is nil" do
    settings = build_settings do
      reads_from env: "WIDGET", credentials: :widget
      setting :api_token
    end

    assert_nil settings.api_token
  end

  # The suite has no mocking library, so a source that answers from memory
  # stands in for one backed by ENV and credentials.
  FakeSource = Struct.new(:env_result, :credentials_result) do
    def env_value(_key) = env_result
    def credentials_value(_key) = credentials_result
  end

  # The ordering rule: every ENV source is tried before any credentials source,
  # NOT source by source. The environment is how a deployment overrides what is
  # baked in, so a fallback prefix must still beat the primary namespace's
  # committed value. Graph::Settings is the real case -- GRAPH_* then
  # REIMBURSEMENTS_*, then the two credentials namespaces.
  test "a fallback ENV source beats the primary credentials source" do
    settings = build_settings { setting :azure_client_id }
    settings.settings_sources << FakeSource.new(nil, "from-primary-creds")
    settings.settings_sources << FakeSource.new("from-fallback-env", nil)

    assert_equal "from-fallback-env", settings.azure_client_id
  end

  test "credentials answer when no ENV source does" do
    settings = build_settings { setting :azure_client_id }
    settings.settings_sources << FakeSource.new(nil, "from-primary-creds")
    settings.settings_sources << FakeSource.new(nil, "from-fallback-creds")

    assert_equal "from-primary-creds", settings.azure_client_id
  end

  test "the first ENV source wins over the second" do
    settings = build_settings do
      reads_from env: "PRIMARY", credentials: :primary
      reads_from env: "FALLBACK", credentials: :fallback
      setting :azure_client_id
    end
    set_env("PRIMARY_AZURE_CLIENT_ID", "from-primary-env")
    set_env("FALLBACK_AZURE_CLIENT_ID", "from-fallback-env")

    assert_equal "from-primary-env", settings.azure_client_id
  end

  test "settings_present? defaults to every declared key" do
    settings = build_settings do
      reads_from env: "WIDGET", credentials: :widget
      setting :one, :two
    end
    set_env("WIDGET_ONE", "1")

    assert_not settings.settings_present?
    set_env("WIDGET_TWO", "2")
    assert settings.settings_present?
  end

  test "settings_present? can be asked about a subset" do
    settings = build_settings do
      reads_from env: "WIDGET", credentials: :widget
      setting :one, :two
    end
    set_env("WIDGET_ONE", "1")

    assert settings.settings_present?(:one)
    assert_not settings.settings_present?(:two)
  end

  test "raw_value stays private so it is not part of a module's public config API" do
    settings = build_settings do
      reads_from env: "WIDGET", credentials: :widget
      setting :api_token
    end

    assert_raises(NoMethodError) { settings.raw_value(:api_token) }
  end
end
