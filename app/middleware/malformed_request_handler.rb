# Answers a Rack::BadRequest (a body or query string Rack cannot parse) with a plain 400. Bots
# post multipart bodies whose boundary never appears, and Rack raises BoundaryTooLongError inside
# Rack::MethodOverride, outside ShowExceptions, so it would be an uncaught 500. Must be inserted
# before Rack::MethodOverride (to rescue it) and inside Honeybadger's ErrorNotifier (so the
# swallowed error is never reported).
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
