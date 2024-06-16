require "test_helper"

class ApplicationIntegrationTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers
  include Devise::Test::IntegrationHelpers
end
