# frozen_string_literal: true

module Pretix
  ##
  # Thin client over the pretix REST API, covering only what the membership sync
  # needs. Goes through the +transport+ callable seam (see HttpTransport) so tests
  # can substitute a plain fake — this suite has no mocking library.
  #
  # INTERFACE ONLY. Bodies are unimplemented; see docs/pretix/membership-sync.md.
  class Client
    class Error < StandardError; end

    # 401/403 from pretix — the token is missing, wrong, or lacks
    # organizer.customers:read/:write.
    class AuthError < Error; end

    # A write was attempted while Settings.writes_enabled? is false.
    class WritesSuppressedError < Error; end

    class_attribute :transport, default: HttpTransport

    def initialize(organizer: Settings::ORGANIZER, token: Settings.api_token)
      @organizer = organizer
      @token = token
    end

    # Every customer for the organizer, following pagination to the end.
    # => Array<Hash> with at least "identifier", "email", "external_identifier".
    def customers
      raise NotImplementedError
    end

    # pretix's only customer filter is an exact-ish email match (iexact).
    # => Hash | nil
    def customer_by_email(email)
      raise NotImplementedError
    end

    # Memberships for the organizer, following pagination. Both filters are
    # optional; +customer+ takes a customer *identifier*.
    # => Array<Hash> with "id", "customer", "membership_type", "date_start", "date_end".
    def memberships(customer: nil, membership_type: nil)
      raise NotImplementedError
    end

    # => Hash of the created membership.
    def create_membership(customer:, membership_type:, date_start:, date_end:)
      raise NotImplementedError
    end

    # pretix refuses DELETE on a membership ("Memberships cannot be deleted. You
    # can change the date instead."), so revoking is a date change like any other.
    # => Hash of the updated membership.
    def update_membership(id, date_end:)
      raise NotImplementedError
    end
  end
end
