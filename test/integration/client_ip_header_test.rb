require "test_helper"

# Cloudflare never sends Client-IP, so one that arrives is spoofed. Left in, a value that disagrees
# with X-Forwarded-For makes remote_ip raise IpSpoofAttackError in the request logger, outside
# ShowExceptions: a bare 500.
class ClientIpHeaderTest < ActionDispatch::IntegrationTest
  test "a spoofed Client-IP is dropped and remote_ip still comes from X-Forwarded-For" do
    get "/robots.txt", headers: { "Client-IP" => "198.51.100.9", "X-Forwarded-For" => "203.0.113.7" }

    assert_response :success
    assert_nil request.get_header("HTTP_CLIENT_IP")
    assert_equal "203.0.113.7", request.remote_ip
  end

  test "remote_ip without a Client-IP header is unchanged" do
    get "/robots.txt", headers: { "X-Forwarded-For" => "203.0.113.7" }

    assert_response :success
    assert_equal "203.0.113.7", request.remote_ip
  end
end
