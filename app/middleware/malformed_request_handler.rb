# Rescues malformed-request errors raised by Rack while parsing the request
# body or query string. Bots probing for Next.js server actions POST
# gzip-encoded multipart bodies whose declared boundary never appears in the
# body, which makes Rack raise Rack::Multipart::BoundaryTooLongError. That is
# raised inside Rack::MethodOverride, which sits *outside*
# ActionDispatch::ShowExceptions, so the error bubbles up as an uncaught 500 and
# gets reported to Honeybadger. Every Rack::BadRequest is a client problem, so
# answer with a plain 400 instead. Must be inserted before Rack::MethodOverride
# (so it can rescue that middleware) and inside Honeybadger's ErrorNotifier (so
# the swallowed error is never reported).
class MalformedRequestHandler
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue Rack::BadRequest => e
    Rails.logger.warn("Malformed request rejected with 400: #{e.class}: #{e.message}")
    [ 400, { "content-type" => "text/plain; charset=utf-8" }, [ "Bad Request" ] ]
  end
end
