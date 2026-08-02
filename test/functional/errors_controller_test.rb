require "test_helper"

class ErrorsControllerTest < ActionController::TestCase
  test "renders the 404 page" do
    get :show, params: { status: "404" }

    assert_response :not_found
    assert_match "isn&#39;t the page you are looking for", response.body
  end

  test "renders the 422 page" do
    get :show, params: { status: "422" }

    assert_response 422
    assert_match "that change was rejected", response.body
  end

  test "renders the 500 page" do
    get :show, params: { status: "500" }

    assert_response :internal_server_error
    assert_match "We have been informed.", response.body
  end

  # Rails picks the status off the exception, so it can dispatch to any of them. The ones with no
  # page of their own still have to answer with their own status.
  test "renders the 500 page under a status that has no page of its own" do
    get :show, params: { status: "503" }

    assert_response :service_unavailable
    assert_match "We have been informed.", response.body
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
