# Suppress frozen-string-literal warnings from the marcel gem (third-party,
# unfixable by us) so they don't obscure test output.
module Warning
  def warn(msg, category: nil)
    super unless msg.include?("/gems/marcel-")
  end
end

if ENV["COVERAGE"]
  require "simplecov"
  require "simplecov-rcov"

  SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
  SimpleCov.command_name "MiniTest"

  SimpleCov.start do
    "rails"
    skip "/test/"
    skip "/config/"
    enable_coverage :branch
  end
end

require "html_acceptance"

ENV["RAILS_ENV"] = "test"

# Outbound Graph sends/replies are gated to production (Settings.outbound_enabled?).
# Tests fake the HTTP transport, so opting in here exercises the send/poll logic
# without any real network call.
ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = "1"

require File.expand_path("../../config/environment", __FILE__)
require "rails/test_help"
require "etc" # Etc.nprocessors, for the parallelize worker cap below

# Shared test helper modules
# FakeHttp first: reimbursements_test_helpers aliases it into its own namespace.
require_relative "support/fake_http"
require_relative "support/import_cache_test_helpers"
require_relative "support/team_membership_test_helpers"
require_relative "support/reimbursements_test_helpers"
require_relative "support/climate_test_helpers"
require_relative "support/rake_task_test_helpers"


class ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include TeamMembershipTestHelpers

  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Rails gives each worker its own database and nothing else; the rest of the
  # shared state is split in parallelize_setup below. PARALLEL_WORKERS=1 to
  # debug serially.
  #
  # Capped rather than :number_of_processors. On a 20-thread i7-12700H: 8
  # workers 38.9s, 12 40.3s, 20 52.1s -- past the physical cores they contend,
  # MySQL most of all (relaxing its per-commit fsync moves the optimum to 12).
  # A no-op on CI, which has fewer cores than the cap.
  parallelize(workers: [ Etc.nprocessors, 8 ].min)

  parallelize_setup do |worker|
    # Otherwise every worker roots at the same tmp/storage, which the teardown
    # below wipes -- one worker deleting another's blobs mid-test.
    service = ActiveStorage::Blob.service
    service.root = "#{service.root}-#{worker}" if service.respond_to?(:root=)

    # Same for the generator tests: all declare tmp/generators, and
    # prepare_destination empties it.
    if defined?(Rails::Generators::TestCase)
      Rails::Generators::TestCase.descendants.each do |klass|
        klass.destination_root = "#{klass.destination_root}-#{worker}"
      end
    end

    # Workers would otherwise overwrite each other's coverage results; a
    # distinct command_name per worker lets SimpleCov merge them instead.
    SimpleCov.command_name("MiniTest-#{worker}") if ENV["COVERAGE"]
  end

  teardown do
    # Deliberately not the hardcoded tmp/storage: under parallelize that is
    # some other worker's data.
    FileUtils.rm_rf(ActiveStorage::Blob.service.try(:root) || Rails.root.join("tmp", "storage"))
    if ENV["VALIDATE"]
      validate_html
    end
  end

  # Run tests with VALIDATE=true to validate all html output.
  # You will need the experimental version of html tidy (which supports HTML5).
  # https://github.com/w3c/tidy-html5
  def validate_html
    return unless defined? response
    return unless response.content_type == "text/html"
    return if response.status == 302

    validation_dir = Rails.root.join "tmp/validation"
    Dir.mkdir(validation_dir) unless File.exist?(validation_dir)
    acceptance = HTMLAcceptance.new(validation_dir, ignore_proprietary: true)

    validator = acceptance.validator(response.body, request.url)
    assert validator.valid?, "Validation error:\n#{validator.exceptions}"
  end
end

class ActionController::TestCase
  include Devise::Test::ControllerHelpers
  include ActionMailer::TestHelper
  include ImportCacheTestHelpers

  teardown do
    # See the note on the ActiveSupport::TestCase teardown above.
    FileUtils.rm_rf(ActiveStorage::Blob.service.try(:root) || Rails.root.join("tmp", "storage"))
  end
end
