require 'simplecov'
require 'simplecov-rcov'
SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
SimpleCov.start 'rails'

require 'html_acceptance'

ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

#Turn off delayed jobs to test mailer
Delayed::Worker.delay_jobs = false

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  teardown do
    if ENV['VALIDATE']
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

    validation_dir = Rails.root.join 'tmp/validation'
    Dir.mkdir(validation_dir) unless File.exists?(validation_dir)
    acceptance = HTMLAcceptance.new(validation_dir, :ignore_proprietary => true)

    validator = acceptance.validator(response.body, request.url)
    assert validator.valid?, "Validation error:\n#{validator.exceptions}"
  end

  def raw_post(action, params, body)
    @request.env['RAW_POST_DATA'] = body
    response = post(action, params)
    @request.env.delete('RAW_POST_DATA')
    response
  end
end

class ActionController::TestCase
  include Devise::TestHelpers
end