require "test_helper"

class ErrorsControllerTest < ActionController::TestCase
  # Rails can dispatch to any status; one with no page of its own still answers with its own status.
  test "renders the 422 page, and the 500 page under a status with no page of its own" do
    { "422" => [ 422, "that change was rejected" ], "503" => [ :service_unavailable, "We have been informed." ] }.each do |status, (code, text)|
      get :show, params: { status: }

      assert_response code
      assert_match text, response.body
    end
  end

  test "reports the exception that was being handled" do
    exception = begin
      raise ArgumentError, "the show could not be converted"
    rescue ArgumentError => e
      e
    end

    @request.env["action_dispatch.exception"] = exception

    get :show, params: { status: "500" }

    assert_response :internal_server_error
    assert_match "the show could not be converted", response.body
    assert_match "ArgumentError", response.body
  end

  # Nothing sets action_dispatch.exception when the path is typed into the address bar, and the
  # error page is built around an exception.
  test "renders without an exception to report" do
    get :show, params: { status: "500" }

    assert_response :internal_server_error
    assert_match "Internal Server Error", response.body
  end
end
