module Reimbursements
  ##
  # App-only (client-credentials) Microsoft Graph auth + JSON request plumbing,
  # shared by MailboxClient (mail folders / receive) and GraphClient (drafts,
  # SharePoint, send). The Entra app is scoped per shared mailbox via an
  # ApplicationAccessPolicy; the same client-credentials token serves every
  # Graph call.
  #
  # The including object must set +@http+ (a transport callable
  # +(method, uri, headers, body) -> [status, body_string]+), +@settings+
  # (responding to azure_tenant_id / azure_client_id / azure_client_secret) and
  # +@clock+ (a +-> { Time }+) in its initializer.
  module GraphAuth
    GRAPH_URL = "https://graph.microsoft.com/v1.0".freeze
    TOKEN_URL = "https://login.microsoftonline.com".freeze

    class Error < StandardError; end

    # Credential problems (expired/revoked client secret) — surfaced to the IT
    # subcommittee rather than retried blindly.
    class AuthError < Error; end

    private

    # Issue a Graph request and return the parsed JSON body ({} when empty).
    # +path+ may be a "/..." Graph path or a full URL (Graph hands back absolute
    # follow-up URLs). Raises AuthError on 401/403, Error on any other non-2xx.
    def graph_request(http_method, path, params: nil, body: nil)
      uri = graph_uri(path, params)
      headers = { "Authorization" => "Bearer #{graph_token}", "Content-Type" => "application/json" }
      status, response_body = @http.call(http_method, uri, headers, body&.to_json)

      raise AuthError, "Graph rejected the token (#{status})" if [ 401, 403 ].include?(status)
      unless (200..299).cover?(status)
        raise Error, "Graph #{http_method.to_s.upcase} #{path} failed (#{status}): " \
                     "#{graph_error_detail(response_body)}"
      end

      response_body.blank? ? {} : JSON.parse(response_body)
    end

    # Authed request whose body is sent verbatim (not JSON-encoded) under an
    # explicit content type — for binary uploads (octet-stream file content).
    # Returns the parsed JSON body.
    def graph_raw_request(http_method, url, raw_body, content_type:)
      headers = { "Authorization" => "Bearer #{graph_token}", "Content-Type" => content_type }
      status, response_body = @http.call(http_method, URI(url), headers, raw_body)

      raise AuthError, "Graph rejected the token (#{status})" if [ 401, 403 ].include?(status)
      unless (200..299).cover?(status)
        raise Error, "Graph #{http_method.to_s.upcase} upload failed (#{status}): " \
                     "#{graph_error_detail(response_body)}"
      end

      response_body.blank? ? {} : JSON.parse(response_body)
    end

    def graph_uri(path, params = nil)
      uri = path.to_s.start_with?("http") ? URI(path) : URI("#{GRAPH_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params
      uri
    end

    # Graph puts the real reason (e.g. ErrorInvalidRecipients for a malformed
    # address) in the JSON error body; surface it instead of an opaque status
    # line. Mirrors bedlam-bacs' _raise_for_graph_error.
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
end
