require "test_helper"

# Signing out, or in again, in another tab replaces the session's CSRF token, so the next save
# from a page already open fails its check. It says so, never with the 500 page.
class StaleAuthenticityTokenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include HoneybadgerTestHelpers

  TURBO_ACCEPT = "text/vnd.turbo-stream.html, text/html, application/xhtml+xml".freeze

  setup do
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    # Only production's rescue_from Exception turns the failure into a reported 500.
    @rails_env = Rails.env.to_s
    Rails.env = "production"
    sign_in users(:admin)
  end

  teardown do
    Rails.env = @rails_env
    ActionController::Base.allow_forgery_protection = @forgery_protection
  end

  test "a Turbo save keeps the page and toasts why nothing was saved" do
    assert_no_difference -> { Department.count } do
      post_with_stale_token admin_departments_path, params: department_params, headers: { "Accept" => TURBO_ACCEPT }
    end

    assert_response :unprocessable_entity
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='toast'][type='error'][message=?]", ApplicationController::STALE_PAGE_MESSAGE
    assert_select "turbo-stream[html]", false, "the message is text, never markup"
  end

  test "an image upload is refused in words the editor shows as written" do
    post_with_stale_token markdown_upload_path,
                          params: { image: fixture_file_upload("test_image.png", "image/png") },
                          headers: { "Accept" => "application/json" }

    assert_response :unprocessable_entity
    assert_equal({ "error" => ApplicationController::STALE_PAGE_MESSAGE }, response.parsed_body)
  end

  test "a fetch that names no format gets JSON, not a redirect" do
    post_with_stale_token markdown_preview_path,
                          params: { input_html: "**hi**" }.to_json,
                          headers: { "Content-Type" => "application/json", "Accept" => "*/*" }

    assert_response :unprocessable_entity
    assert_equal ApplicationController::STALE_PAGE_MESSAGE, response.parsed_body["error"]
  end

  test "a plain form submit goes back to its page and says to try again" do
    assert_no_difference -> { Department.count } do
      post_with_stale_token admin_departments_path,
                            params: department_params,
                            headers: { "Accept" => "text/html,application/xhtml+xml,*/*;q=0.8",
                                       "Referer" => new_admin_department_url }
    end

    assert_redirected_to new_admin_department_url
    assert_equal ApplicationController::STALE_FORM_MESSAGE, flash[:alert]
  end

  test "a post from another site is refused without blaming a stale page" do
    post_with_stale_token admin_departments_path,
                          params: department_params,
                          headers: { "Accept" => TURBO_ACCEPT, "Origin" => "https://elsewhere.example" }

    assert_response :unprocessable_entity
    assert_no_match "out of date", response.body
  end

  private

  def department_params = { department: { name: "Puppetry", match_terms: "puppeteer" } }

  # Posts with a token from before the session changed. It is expected, so nothing is reported.
  def post_with_stale_token(path, headers:, **)
    notices = capture_honeybadger_notices do
      post(path, headers: headers.merge("X-CSRF-Token" => "from-before-signing-in-again"), **)
    end

    assert_empty notices
  end
end
