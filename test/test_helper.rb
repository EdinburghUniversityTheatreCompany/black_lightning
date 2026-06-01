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
    add_filter "/test/"
    add_filter "/config/"
    enable_coverage :branch
  end
end

require "html_acceptance"

ENV["RAILS_ENV"] = "test"

require File.expand_path("../../config/environment", __FILE__)
require "rails/test_help"


class ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include BLFactoryRoleHelper

  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  setup { Prosopite.scan }

  teardown do
    Prosopite.finish
    # Reset factory caches so rolled-back records don't leak to the next test
    $bl_cached_venue_id = nil
    $bl_cached_show = nil
    $bl_role_cache = nil
    $bl_cached_user_id = nil
    FileUtils.rm_rf(Rails.root.join("tmp", "storage"))
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

  teardown do
    FileUtils.rm_rf(Rails.root.join("tmp", "storage"))
  end
end
