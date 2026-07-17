module Reimbursements
  ##
  # Default HTTP transport for the reimbursements service clients
  # (Airtable, Gemini, Graph). Callable as
  # +(method, uri, headers, body) -> [status, body_string, response_headers]+ so
  # tests can substitute a plain fake (this suite has no mocking library).
  # +response_headers+ is a flat {lower-case-name => value} hash; callers that
  # only need status + body destructure the first two and ignore it. The Airtable
  # client uses it to honour a 429 Retry-After header.
  module HttpTransport
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    def self.call(http_method, uri, headers, body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        request = Net::HTTP.const_get(http_method.to_s.capitalize).new(uri, headers)
        request.body = body if body
        http.request(request)
      end
      [ response.code.to_i, response.body, response.each_header.to_h ]
    end
  end
end
