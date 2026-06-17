require "test_helper"

# Bots probing for Next.js server actions POST gzip-encoded multipart bodies
# whose declared boundary never appears in the body, which makes Rack raise
# Rack::Multipart::BoundaryTooLongError while parsing params. That happens inside
# Rack::MethodOverride — outside ActionDispatch::ShowExceptions — so without a
# handler it bubbles up as an uncaught 500 and gets reported to Honeybadger.
# It is always a malformed client request and should return a plain 400.
class MalformedRequestTest < ActionDispatch::IntegrationTest
  test "malformed multipart body returns 400, not a 500" do
    post "/",
      params: "x" * 20_000,
      headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=WebKitFormBoundaryc5a6313a11ed585991e36991f57d8d07" }

    assert_response :bad_request
  end
end
