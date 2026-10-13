# App-only (client-credentials) Graph auth and JSON request plumbing, shared by
# Graph::MailboxClient and Reimbursements::GraphClient. The Entra app carries NO mail
# permission: Exchange scopes it to named mailboxes via RBAC for Applications
# (docs/graph-mailbox-rbac.md). SharePoint stays an Entra grant, which RBAC cannot express.
#
# The includer's initializer sets +@http+ (+(method, uri, headers, body) -> [status, body_string]+),
# +@settings+ (azure_tenant_id / azure_client_id / azure_client_secret) and +@clock+, and may set
# +@sleeper+ (+->(seconds)+, the test seam for the retry pause).
module GraphAuth
  GRAPH_URL = "https://graph.microsoft.com/v1.0".freeze
  TOKEN_URL = "https://login.microsoftonline.com".freeze

  # Graph's gateway briefly answers these now and then. A GET is retried once; a write never,
  # because a 502 does not say whether the first attempt landed and a replayed reply is a
  # second email to a producer.
  TRANSIENT_STATUSES = [ 502, 503, 504 ].freeze
  TRANSIENT_RETRY_DELAY = 2

  class Error < StandardError; end

  # Credential problems (expired or revoked secret): alerted to IT rather than retried.
  class AuthError < Error; end

  # A 403: the token is good, but the app may not touch that resource (a mailbox outside the
  # Exchange scope, a site with no Sites.Selected grant). An AuthError, so every rescue of one
  # still catches it; only the Settings access check tells the two apart.
  class AccessDeniedError < AuthError; end

  # A 404 from Graph. The mailbox mutation paths swallow it only once a re-GET confirms the
  # message is really gone (Graph::MailboxClient#swallow_only_if_gone); everywhere else it is a
  # real failure, and a subclass of Error so existing rescues still catch it.
  class NotFoundError < Error; end

  # An outbound side effect was refused (not production, REIMBURSEMENTS_ENABLE_OUTBOUND unset).
  # Raised rather than returning a plausible value, so a suppressed result is never mistaken for
  # success (GraphClient#upload_to_folder, #delete_message). A subclass of Error so best-effort
  # rescues contain it.
  class OutboundSuppressedError < Error; end

  private

  # Returns the parsed JSON body ({} when empty). +path+ may be a "/..." path or a full URL
  # (Graph returns absolute follow-up URLs). Raises AuthError on 401, AccessDeniedError on 403,
  # Error on other non-2xx.
  def graph_request(http_method, path, params: nil, body: nil)
    uri = graph_uri(path, params)
    json = body&.to_json
    status, response_body = send_graph_request(http_method, uri, json)
    if http_method == :get && TRANSIENT_STATUSES.include?(status)
      (@sleeper || method(:sleep)).call(TRANSIENT_RETRY_DELAY)
      status, response_body = send_graph_request(http_method, uri, json)
    end

    parse_graph_response(status, response_body, "#{http_method.to_s.upcase} #{path}")
  end

  def send_graph_request(http_method, uri, body, content_type: "application/json")
    headers = { "Authorization" => "Bearer #{graph_token}", "Content-Type" => content_type }
    @http.call(http_method, uri, headers, body)
  end

  # For binary uploads: the body is sent verbatim under an explicit content type.
  def graph_raw_request(http_method, url, raw_body, content_type:)
    status, response_body = send_graph_request(http_method, URI(url), raw_body, content_type: content_type)
    parse_graph_response(status, response_body, "#{http_method.to_s.upcase} upload")
  end

  def parse_graph_response(status, response_body, label)
    raise AccessDeniedError, "Graph rejected the token (403)" if status == 403
    raise AuthError, "Graph rejected the token (401)" if status == 401
    unless (200..299).cover?(status)
      error_class = status == 404 ? NotFoundError : Error
      raise error_class, "Graph #{label} failed (#{status}): #{graph_error_detail(response_body)}"
    end

    response_body.blank? ? {} : JSON.parse(response_body)
  end

  def graph_uri(path, params = nil)
    uri = path.to_s.start_with?("http") ? URI(path) : URI("#{GRAPH_URL}#{path}")
    uri.query = URI.encode_www_form(params) if params
    uri
  end

  # Surfaces Graph's reason (e.g. ErrorInvalidRecipients) instead of an opaque status line.
  def graph_error_detail(response_body)
    error = JSON.parse(response_body.to_s)["error"] || {}
    [ error["code"], error["message"] ].reject(&:blank?).join(": ").presence ||
      response_body.to_s.truncate(200)
  rescue JSON::ParserError
    response_body.to_s.truncate(200)
  end

  def graph_token
    return @graph_token if @graph_token && @graph_token_expires_at&.after?(@clock.call + 60)

    fetch_graph_token
  end

  def fetch_graph_token
    uri = URI("#{TOKEN_URL}/#{@settings.azure_tenant_id}/oauth2/v2.0/token")
    form = URI.encode_www_form(
      client_id: @settings.azure_client_id,
      client_secret: @settings.azure_client_secret,
      scope: "https://graph.microsoft.com/.default",
      grant_type: "client_credentials"
    )
    status, response_body = @http.call(:post, uri,
                                       { "Content-Type" => "application/x-www-form-urlencoded" }, form)

    unless status == 200
      message = "Graph token request failed (#{status}): #{response_body.to_s.truncate(300)}"
      raise AuthError, message if [ 400, 401 ].include?(status)

      raise Error, message
    end

    data = JSON.parse(response_body)
    @graph_token_expires_at = @clock.call + data.fetch("expires_in", 3600).to_i
    @graph_token = data.fetch("access_token")
  end
end
