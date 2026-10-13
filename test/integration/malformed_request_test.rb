require "test_helper"

# A multipart body whose boundary never appears makes Rack raise inside Rack::MethodOverride,
# outside ShowExceptions, so only MalformedRequestHandler stands between it and a 500.
class MalformedRequestTest < ActionDispatch::IntegrationTest
  test "malformed multipart body returns 400, not a 500" do
    post "/",
      params: "x" * 20_000,
      headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=WebKitFormBoundaryc5a6313a11ed585991e36991f57d8d07" }

    assert_response :bad_request
  end
end
