class CloudflareIpSanitizer
  CACHE_KEY = "cloudflare_ips"

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    if from_cloudflare?(request)
      # Remove spoofed CLIENT_IP header - Cloudflare doesn't set this
      env.delete("HTTP_CLIENT_IP")
    end

    @app.call(env)
  end

  private

  def from_cloudflare?(request)
    return false unless request.ip.present?

    cloudflare_ips.any? { |range| range.include?(request.ip) }
  end

  def cloudflare_ips
    Rails.cache.fetch(CACHE_KEY) { CloudflareIps.fallback }
  end
end
