# Drops the Client-IP header before ActionDispatch::RemoteIp reads it. Cloudflare never sends one,
# so it is always spoofed, and a value disagreeing with X-Forwarded-For makes remote_ip raise
# IpSpoofAttackError in the request logger, outside ShowExceptions: a bare 500.
class ClientIpStripper
  def initialize(app)
    @app = app
  end

  def call(env)
    env.delete("HTTP_CLIENT_IP")
    @app.call(env)
  end
end
