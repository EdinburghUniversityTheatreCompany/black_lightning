require "test_helper"

class Display::SetupControllerTest < ActionController::TestCase
  # A renamed route helper raises in playlist, so a dead URL fails this test.
  test "lists every playlist url as a link with its duration, and is not indexed" do
    get :show

    assert_match "noindex", response.headers["X-Robots-Tag"]
    Display::SetupController.playlist.each do |entry|
      assert_select "a[href=?]", "#{request.base_url}#{entry[:path]}"
      assert_match "#{entry[:seconds]}s", response.body
    end
  end
end
