# frozen_string_literal: true

module Pretix
  ##
  # Thin client over the pretix REST API, covering only what the membership sync
  # needs. Takes its HTTP transport and its settings as constructor seams so tests
  # can substitute plain fakes — this suite has no mocking library.
  #
  # See docs/pretix/membership-sync.md.
  class Client
    class Error < StandardError; end

    # 401/403 from pretix — the token is missing, wrong, or lacks
    # organizer.customers:read/:write.
    class AuthError < Error; end

    # A write was attempted while the injected settings' writes_enabled? is false.
    class WritesSuppressedError < Error; end

    # pretix does not know that URL. Its own subclass because a stale stored
    # customer link is a fact about our data, not a failure worth aborting over.
    class NotFoundError < Error; end

    AUTH_STATUSES = [ 401, 403 ].freeze

    # How much of a failure body reaches the exception message. Long enough for
    # pretix's {"detail": "..."} and its field-level validation errors, short
    # enough that a stray HTML error page doesn't fill the log.
    BODY_EXCERPT = 300

    # pretix pages at 50, so ~875 customers is 18 pages. The cap exists because
    # these run unattended: a self-referential "next" would spin forever.
    MAX_PAGES = 500

    # pretix Hosted allows 360/minute per organizer and may disable API access
    # for a client that keeps bursting after a 429, so pacing is a requirement.
    # Set under the limit to leave headroom for anything else on the token.
    # Invisible locally: the round trip from a developer machine is slow enough
    # to stay under it by accident, from the app container it is not.
    MAX_REQUESTS_PER_MINUTE = 300
    MIN_REQUEST_INTERVAL = 60.0 / MAX_REQUESTS_PER_MINUTE

    THROTTLED_STATUS = 429
    NOT_FOUND_STATUS = 404

    # Retried rather than raised: the reconcile has no resume point, so a run
    # dying halfway leaves the shop half-synced with no record of where.
    MAX_THROTTLE_RETRIES = 5

    # Used when a 429 arrives without a parseable Retry-After.
    DEFAULT_RETRY_AFTER = 30

    # The sales channel availability is asked about. The website is the only one
    # this organizer sells through, and it is what a visitor to our own show page
    # would see.
    WEB_SALES_CHANNEL = "web".freeze

    # All defaulted: the sync builds a bare Pretix::Client.new. +http+ and
    # +settings+ are injected as GraphClient and Climate::OpenMeteoClient take
    # theirs, so a test fakes them per instance rather than mutating anything
    # this parallelising suite shares.
    # +sleeper+ is a seam so tests exercise the pacing and the throttle retry
    # without actually waiting.
    def initialize(organizer: Settings::ORGANIZER, token: Settings.api_token,
                   http: HttpTransport, settings: Settings, sleeper: ->(seconds) { sleep(seconds) })
      @organizer = organizer
      @token = token
      @http = http
      @settings = settings
      @sleeper = sleeper
      @last_request_finished_at = nil
    end

    # Every customer for the organizer, following pagination to the end.
    # => Array<Hash> with at least "identifier", "email", "external_identifier".
    def customers
      paginated("customers/")
    end

    # One customer by pretix's own key for the account, which is what
    # User#pretix_customer_identifier stores. Unlike the email filter it cannot
    # go stale when someone changes address.
    # => Hash, or nil if pretix no longer knows that identifier.
    def customer(identifier)
      return nil if identifier.blank?

      request(:get, "customers/#{identifier}/")
    rescue NotFoundError
      nil
    end

    # pretix's only customer filter is an exact-ish email match (iexact).
    # => Hash | nil
    def customer_by_email(email)
      matches = paginated("customers/", email: email)
      return nil if matches.empty?
      return matches.first if matches.one?

      # Unreachable as pretix models it — the customer table has a unique email
      # constraint per organizer, which is the very constraint that breaks a
      # member's login when an account is pre-created. If it ever does happen,
      # picking one arbitrarily would attach a membership to the wrong account
      # and there is nothing here that could tell which, so fail loudly. Only
      # the single-user sync calls this; the nightly reconcile lists instead, so
      # raising costs one person's sync rather than the whole run.
      raise Error, "pretix returned #{matches.size} customers for #{email}"
    end

    # Every subevent (dated performance) of one event SERIES, following pagination.
    # +slug+ is the series slug, which is what Event#pretix_slug holds.
    #
    # Availability is requested explicitly: without with_availability_for the
    # response carries no best_availability_state at all, so nothing could tell a
    # sold-out date from an available one. pretix documents 100 as "available",
    # anything below as "sold out or reserved", and null as "status unknown".
    #
    # Unlike the whole-organizer membership list, this one is safe to page: it is
    # scoped to a single series, so it is a handful of rows rather than the
    # hundreds that made pretix's unordered LIMIT/OFFSET repeat and drop entries.
    # => Array<Hash> with "id", "date_from", "date_to", "date_admission",
    #    "active", "is_public" and "best_availability_state".
    def subevents(slug, availability_channel: WEB_SALES_CHANNEL)
      paginated("events/#{slug}/subevents/", with_availability_for: availability_channel)
    end

    # Memberships for the organizer, following pagination. Both filters are
    # optional; +customer+ takes a customer *identifier*.
    #
    # Both filter names verified against the live organizer (Aug 2026), because
    # a filter pretix does not recognise is silently ignored and hands back the
    # WHOLE list — a reconcile would then read every one of the 849 memberships
    # as belonging to the one customer it asked about. ?customer=<identifier>
    # returned 2 of 849, all that customer's; ?membership_type=225 returned 837,
    # all type 225; and a bogus ?customer=DOESNOTEXIST returned 0 rather than
    # everything, which is what rules the silent-ignore case out. Matches
    # pretix's MembershipFilter, which maps +customer+ to customer__identifier
    # with iexact.
    # => Array<Hash> with "id", "customer", "membership_type", "date_start", "date_end".
    def memberships(customer: nil, membership_type: nil)
      filters = { customer: customer, membership_type: membership_type }.compact
      paginated("memberships/", **filters)
    end

    # => Hash of the created membership.
    def create_membership(customer:, membership_type:, date_start:, date_end:)
      refuse_write!("create a #{membership_type} membership for #{customer}")

      request(:post, "memberships/",
              body: { customer: customer, membership_type: membership_type,
                      date_start: timestamp(date_start), date_end: timestamp(date_end) })
    end

    # pretix refuses DELETE on a membership ("Memberships cannot be deleted. You
    # can change the date instead."), so revoking is a date change like any other.
    # => Hash of the updated membership.
    def update_membership(id, date_end:)
      refuse_write!("move membership #{id}'s date_end")

      request(:patch, "memberships/#{id}/", body: { date_end: timestamp(date_end) })
    end

    private

    # Walks pretix's "next" links, which are absolute URLs, to the end of the list.
    def paginated(path, **params)
      page = request(:get, path, params: params)
      results = []

      MAX_PAGES.times do
        results.concat(Array(page["results"]))
        next_url = page["next"]
        return results if next_url.blank?

        page = request(:get, next_url)
      end

      raise Error, "pretix paginated past #{MAX_PAGES} pages for #{path}"
    end

    def request(http_method, path, params: nil, body: nil)
      raise AuthError, "no pretix API token is configured" if @token.blank?

      uri = build_uri(path, params)
      status, response_body, response_headers = send_paced(http_method, uri, body)

      MAX_THROTTLE_RETRIES.times do
        break unless status == THROTTLED_STATUS

        @sleeper.call(retry_after(response_headers, response_body))
        status, response_body, response_headers = send_paced(http_method, uri, body)
      end

      check!(http_method, uri, status, response_body)
      parse(response_body, uri)
    end

    # Measured from the END of the previous request, so a slow response — which
    # already spent the interval on the wire — is not made to wait again.
    def send_paced(http_method, uri, body)
      wait = pacing_delay
      @sleeper.call(wait) if wait.positive?

      result = @http.call(http_method, uri, headers, body&.to_json)
      @last_request_finished_at = monotonic_now
      result
    end

    def pacing_delay
      return 0 if @last_request_finished_at.nil?

      MIN_REQUEST_INTERVAL - (monotonic_now - @last_request_finished_at)
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # pretix sends Retry-After on a 429. The body's "Expected available in N
    # seconds" is read only as a fallback, since the header is the contract.
    def retry_after(response_headers, response_body)
      header = response_headers.is_a?(Hash) ? response_headers["retry-after"] : nil
      seconds = header.to_s[/\d+/] || response_body.to_s[/available in (\d+) second/, 1]
      # A second of slack: waiting exactly the stated window occasionally lands
      # back inside it and burns a retry.
      return DEFAULT_RETRY_AFTER if seconds.blank?

      (seconds.to_i + 1).clamp(1, 300)
    end

    # Every message here is built from the method, the path, the status and the
    # body: the Authorization header must never reach a log or a Honeybadger
    # notice, and an API token is a bearer credential for the whole organizer.
    def check!(http_method, uri, status, response_body)
      if AUTH_STATUSES.include?(status)
        raise AuthError, "pretix rejected the API token (HTTP #{status}) " \
                         "on #{http_method.to_s.upcase} #{uri.path}"
      end
      return if (200..299).cover?(status)

      error_class = status == NOT_FOUND_STATUS ? NotFoundError : Error
      raise error_class, "pretix #{http_method.to_s.upcase} #{uri.path} failed (HTTP #{status}): " \
                         "#{response_body.to_s.truncate(BODY_EXCERPT)}"
    end

    def parse(response_body, uri)
      return {} if response_body.blank?

      JSON.parse(response_body)
    rescue JSON::ParserError
      # A gateway or WAF page in front of pretix answers 200 with HTML; letting
      # the raw JSON error out would name neither the endpoint nor the body.
      raise Error, "pretix returned an unreadable body from #{uri.path}: " \
                   "#{response_body.to_s.truncate(BODY_EXCERPT)}"
    end

    def build_uri(path, params = nil)
      # A "next" link is absolute and already carries its own query.
      uri = path.to_s.start_with?("http") ? URI(path) : URI.join(Settings::API_BASE, organizer_path(path))
      uri.query = URI.encode_www_form(params) if params.present?
      uri
    end

    def organizer_path(path)
      "organizers/#{@organizer}/#{path}"
    end

    def headers
      { "Authorization" => "Token #{@token}", "Content-Type" => "application/json" }
    end

    # pretix compares a membership window against a show's date_from, so a bare
    # date would be read at UTC midnight and shift the boundary an hour through
    # BST. Always send the offset, and resolve it in the app's zone.
    def timestamp(value)
      value.in_time_zone.iso8601
    end

    def refuse_write!(description)
      return if @settings.writes_enabled?

      # There is one live pretix organizer and no staging copy, so a dev machine
      # holding a token must not touch real members' pricing. Raising (rather
      # than returning a plausible hash) keeps a suppressed write from being
      # recorded as done.
      raise WritesSuppressedError,
            "pretix writes are disabled here (set PRETIX_ENABLE_WRITES): #{description}"
    end
  end
end
