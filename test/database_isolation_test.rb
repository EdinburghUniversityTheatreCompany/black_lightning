require "test_helper"

# WORKTREE_DB_SUFFIX gives each git worktree or background agent its own databases. These
# pin all four, because the failure is silent: you get someone else's data, not an error.
class DatabaseIsolationTest < ActiveSupport::TestCase
  ISOLATED_KEYS = [
    %w[development primary],
    %w[development queue],
    %w[development cache],
    %w[test]
  ].freeze

  test "every dev and test database name carries WORKTREE_DB_SUFFIX when it is set" do
    config = load_database_yml("_agent7")

    ISOLATED_KEYS.each do |path|
      name = config.dig(*path)["database"]
      assert_match(/_agent7/, name, "#{path.join('.')} database ignores WORKTREE_DB_SUFFIX")
    end
  end

  test "the suffix defaults to empty so the main checkout keeps the plain names" do
    config = load_database_yml(nil)

    assert_equal "bedlam_blacklightning_development", config.dig("development", "primary")["database"]
    assert_equal "bedlam_blacklightning_development_queue", config.dig("development", "queue")["database"]
    assert_equal "bedlam_blacklightning_development_cache", config.dig("development", "cache")["database"]
    assert_equal "bedlam_blacklightning_test", config["test"]["database"]
  end

  # Production must NOT interpolate it: a stray variable in the deployed environment would
  # point the app at a database that does not exist.
  test "production database names are fixed" do
    config = load_database_yml("_agent7")

    %w[primary queue cache].each do |name|
      assert_no_match(/_agent7/, config.dig("production", name)["database"])
    end
  end

  private

  def load_database_yml(suffix)
    previous = ENV["WORKTREE_DB_SUFFIX"]
    ENV["WORKTREE_DB_SUFFIX"] = suffix
    rendered = ERB.new(Rails.root.join("config/database.yml").read).result
    YAML.safe_load(rendered, aliases: true)
  ensure
    ENV["WORKTREE_DB_SUFFIX"] = previous
  end
end
