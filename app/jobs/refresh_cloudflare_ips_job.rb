class RefreshCloudflareIpsJob < ApplicationJob
  queue_as :default

  URLS = {
    ipv4: "https://www.cloudflare.com/ips-v4",
    ipv6: "https://www.cloudflare.com/ips-v6"
  }.freeze

  def perform
    ips = fetch_ips
    Rails.cache.write(CloudflareIpSanitizer::CACHE_KEY, ips, expires_in: 24.hours)
    Rails.logger.info "Refreshed Cloudflare IPs: #{ips.size} ranges"
  rescue => e
    Rails.logger.error "Failed to refresh Cloudflare IPs: #{e.message}"
    Honeybadger.notify(e)
  end

  private

  def fetch_ips
    ips = []
    URLS.each_value do |url|
      response = Net::HTTP.get(URI(url))
      ips.concat(response.split("\n").map { |ip| IPAddr.new(ip.strip) })
    end
    ips
  end
end
