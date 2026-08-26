# frozen_string_literal: true

module Pretix
  ##
  # Thin client over the pretix REST API, covering only what the membership sync
  # needs. Goes through the +transport+ callable seam (see HttpTransport) so tests
  # can substitute a plain fake — this suite has no mocking library.
  #
  # See docs/pretix/membership-sync.md.
  class Client
    class Error < StandardError; end

    # 401/403 from pretix — the token is missing, wrong, or lacks
    # organizer.customers:read/:write.
    class AuthError < Error; end

    # A write was attempted while Settings.writes_enabled? is false.
    class WritesSuppressedError < Error; end

    AUTH_STATUSES = [ 401, 403 ].freeze

    # How much of a failure body reaches the exception message. Long enough for
    # pretix's {"detail": "..."} and its field-level validation errors, short
    # enough that a stray HTML error page doesn't fill the log.
    BODY_EXCERPT = 300

    # pretix pages at 50 results, so ~875 customers is 18 pages. The cap only
    # exists because these calls run unattended from the nightly reconcile: a
    # "next" that ever pointed at its own page would otherwise spin forever
    # rather than fail.
    MAX_PAGES = 500

    class_attribute :transport, default: HttpTransport

    def initialize(organizer: Settings::ORGANIZER, token: Settings.api_token)
      @organizer = organizer
      @token = token
    end

    # Every customer for the organizer, following pagination to the end.
    # => Array<Hash> with at least "identifier", "email", "external_identifier".
    def customers
      paginated("customers/")
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

    # Memberships for the organizer, following pagination. Both filters are
    # optional; +customer+ takes a customer *identifier*.
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
      status, response_body = transport.call(http_method, uri, headers, body&.to_json)

      check!(http_method, uri, status, response_body)
      parse(response_body, uri)
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

      raise Error, "pretix #{http_method.to_s.upcase} #{uri.path} failed (HTTP #{status}): " \
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
      return if Settings.writes_enabled?

      # There is one live pretix organizer and no staging copy, so a dev machine
      # holding a token must not touch real members' pricing. Raising (rather
      # than returning a plausible hash) keeps a suppressed write from being
      # recorded as done.
      raise WritesSuppressedError,
            "pretix writes are disabled here (set PRETIX_ENABLE_WRITES): #{description}"
    end
  end
end
