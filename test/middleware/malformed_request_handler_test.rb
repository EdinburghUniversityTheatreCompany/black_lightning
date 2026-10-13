require "test_helper"

class MalformedRequestHandlerTest < ActiveSupport::TestCase
  # What Rack does on an unparseable multipart body.
  RAISING_APP = ->(_env) { raise Rack::Multipart::BoundaryTooLongError, "multipart boundary not found within limit" }
  OK_APP = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }

  # Rack::Lint fails a 400 that breaks the Rack 3 SPEC (e.g. a header name not lowercase).
  test "rescues Rack::BadRequest and returns a Rack-spec-compliant 400" do
    app = Rack::Lint.new(MalformedRequestHandler.new(RAISING_APP))

    status, _headers, body = app.call(Rack::MockRequest.env_for("/", method: "POST"))

    assert_equal 400, status
    assert_equal "Bad Request", read_body(body)
  end

  test "passes valid requests through untouched" do
    app = Rack::Lint.new(MalformedRequestHandler.new(OK_APP))

    status, _headers, body = app.call(Rack::MockRequest.env_for("/"))

    assert_equal 200, status
    assert_equal "ok", read_body(body)
  end

  private

  def read_body(body)
    buffer = +""
    body.each { |chunk| buffer << chunk }
    buffer
  ensure
    body.close if body.respond_to?(:close)
  end
end
