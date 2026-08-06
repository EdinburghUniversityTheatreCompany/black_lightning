# Fake transport compatible with HttpTransport's contract: responds with queued
# [status, body] pairs (or [status, body, headers] where the client reads a
# response header) and records every request. Shared by the reimbursements Graph
# clients and the climate Govee/Open-Meteo clients — this suite has no mocking
# library, so a hand-written fake injected through a +http:+ argument is how any
# outbound client gets tested.
class FakeHttp
  Request = Struct.new(:method, :uri, :headers, :body)

  attr_reader :requests

  def initialize(responses)
    @responses = responses
    @requests = []
  end

  def call(http_method, uri, headers, body)
    @requests << Request.new(http_method, uri.to_s, headers, body)
    response = @responses.shift || raise("FakeHttp exhausted after #{@requests.size} requests")
    # A queued Exception simulates a transport-level failure (timeout, DNS,
    # TLS) rather than an ordinary HTTP response.
    raise response if response.is_a?(Exception)

    response
  end
end
