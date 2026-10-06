# Fake for HttpTransport: answers queued [status, body(, headers)] responses, or raises a
# queued Exception (a transport failure: timeout, DNS, TLS), and records each request.
# Injected through a client's +http:+ argument.
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
    raise response if response.is_a?(Exception)

    response
  end
end
