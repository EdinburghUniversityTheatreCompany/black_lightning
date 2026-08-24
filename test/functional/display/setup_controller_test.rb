require "test_helper"

class Display::SetupControllerTest < ActionController::TestCase
  test "lists every display url with a suggested duration" do
    get :show

    assert_response :success

    Display::SetupController.playlist.each do |entry|
      assert_match entry[:path], response.body, "#{entry[:path]} is missing from the setup page"
      assert_match "#{entry[:seconds]}s", response.body
    end
  end

  # A volunteer copies these into a Raspberry Pi that then plays them forever.
  # A renamed route must fail here, not silently leave the page listing dead
  # URLs that nobody re-checks.
  test "every playlist path resolves to a display controller" do
    Display::SetupController.playlist.each do |entry|
      recognized = Rails.application.routes.recognize_path(entry[:path])

      assert_includes %w[display/pages display/setup], recognized[:controller],
                      "#{entry[:path]} does not reach a display controller"
    end
  end

  test "every playlist url is a clickable link" do
    get :show

    Display::SetupController.playlist.each do |entry|
      assert_select "a[href=?]", "#{request.base_url}#{entry[:path]}"
    end
  end

  test "the setup page is not indexed" do
    get :show

    assert_match "noindex", response.headers["X-Robots-Tag"]
  end
end
