require "test_helper"

# Covers the routing half of ErrorsController: an exception no controller rescued comes back
# through the routes as a fresh GET of "/<status>" with the exception in the Rack env, and used to
# fall through to the static catch-all and be answered with the 404 page.
class ErrorPagesTest < ActionDispatch::IntegrationTest
  PAGE_NOT_FOUND = "isn&#39;t the page you are looking for".freeze

  test "a re-dispatched server error renders the 500 page, not the 404 page" do
    get "/500", env: { "action_dispatch.exception" => failure("something went wrong") }

    assert_response :internal_server_error
    assert_match "We have been informed.", response.body
    assert_match "something went wrong", response.body
    assert_no_match PAGE_NOT_FOUND, response.body
  end

  test "a re-dispatched not found renders the 404 page" do
    get "/404", env: { "action_dispatch.exception" => failure("no such show", ActiveRecord::RecordNotFound) }

    assert_response :not_found
    assert_match PAGE_NOT_FOUND, response.body
  end

  test "the error routes do not shadow the static pages" do
    get "/accessibility"

    assert_response :success
  end

  private

  # Raised rather than built, so that a failing assertion can print the exception's backtrace
  # instead of blowing up on a nil one.
  def failure(message, klass = StandardError)
    raise klass, message
  rescue klass => e
    e
  end
end
