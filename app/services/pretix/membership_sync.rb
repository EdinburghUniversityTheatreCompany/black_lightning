# frozen_string_literal: true

module Pretix
  # Drives each pretix customer's ONE membership from the website's +member+ /
  # +life member+ roles. See docs/pretix/membership-sync.md.
  #
  #   sync_user(user)  => Symbol, one of OUTCOMES
  #   reconcile_all    => Hash of counts, one key per outcome
  #
  # SAFETY BIAS: a wrong "not entitled" revokes a real person's pricing; a wrong
  # "entitled" costs one discounted seat. So every ambiguity writes nothing. Only a
  # customer resolving to a User who demonstrably lacks the role is expired.
  class MembershipSync
    include ErrorReporting

    # Compared downcased.
    ENTITLING_ROLES = [ "member", "life member" ].freeze

    # Slack past the end of the academic year, for the manual September rollover.
    GRACE = 3.weeks

    # Refresh date_end only once it is nearer than this AND differs from the
    # target: the window alone would re-write the same date nightly from March.
    REFRESH_WINDOW = 18.months

    # The customer list is paged without a unique tiebreaker, so a pass can miss
    # rows: repeat until one finds nothing to do. The cap stops a bug looping forever.
    MAX_PASSES = 5

    OUTCOMES = %i[
      created extended expired deduplicated unchanged
      no_customer no_identifier no_user ambiguous suppressed failed
    ].freeze

    # Writes accumulate across passes; every other count is the final pass's snapshot.
    CUMULATIVE_COUNTS = %i[created extended expired deduplicated duplicates_expired].freeze

    Patch = Data.define(:membership_id, :date_end)
    Creation = Data.define(:date_start, :date_end)

    # What one customer needs: at most one creation, at most one patch of the
    # canonical record, and a patch per duplicate being collapsed.
    Plan = Data.define(:outcome, :creation, :canonical_patch, :duplicate_patches) do
      def self.none(outcome) = new(outcome: outcome, creation: nil, canonical_patch: nil, duplicate_patches: [])

      def patches = [ canonical_patch, *duplicate_patches ].compact

      def writes? = creation.present? || patches.any?
    end

    Result = Data.define(:outcome, :duplicates_expired)

    # End of the NEXT academic year plus GRACE, end of day. pretix validates a
    # membership against the SHOW's date, not the purchase date, so this must
    # reach every show on sale; it still expires by itself within two years if
    # the sync dies. From Aug 2026 that is 2027-09-21T23:59:59+01:00.
    def self.membership_end(now = Time.zone.now)
      start_year = ApplicationController.helpers.date_to_academic_year(now.to_date)
      (Date.new(start_year + 2, 8, 31) + GRACE).end_of_day.change(usec: 0)
    end

    def initialize(client: Pretix::Client.new)
      @client = client
    end

    # Straight after a login or a role change. The nightly reconcile is what
    # guarantees correctness; this only makes it feel immediate.
    def sync_user(user)
      return :no_customer if user.blank? || user.email.blank?

      guarded(user.email) do
        linked = @client.customer(user.pretix_customer_identifier)
        customer = linked.presence || @client.customer_by_email(user.email)
        next skipped(:no_customer) if customer.blank?
        # Only for an email match: a linked customer is this person by
        # construction, and requiring the emails to agree would undo the link on
        # the very address change it exists to survive.
        if linked.blank? && external_email(customer) != normalize(user.email)
          next skipped(:no_identifier)
        end

        identifier = customer["identifier"]
        remember_link(user, identifier) if linked.blank?
        apply(plan_for(entitled: entitled?(user), memberships: fetch_memberships(customer: identifier)),
              customer: identifier)
      end.outcome
    end

    # One customer list per pass, then one membership read per customer that
    # resolves to a User (see reconcile_customer).
    #
    # A failure on the customer list is deliberately NOT caught: it is fatal for
    # every customer, and a run that carried on would report a shop full of
    # customers with no memberships. Per-customer failures are caught and counted.
    def reconcile_all
      totals = blank_counts
      passes = 0

      MAX_PASSES.times do
        passes += 1
        counts = reconcile_pass
        totals = merge_counts(totals, counts)
        break unless CUMULATIVE_COUNTS.any? { |key| counts[key].positive? }
      end

      totals.merge(passes: passes)
    end

    private

    def reconcile_pass
      counts = blank_counts
      customers = @client.customers
      users = users_by_email(customers)
      linked_users = users_by_link(customers)

      customers.each do |customer|
        result = reconcile_customer(customer, users, linked_users)
        counts[result.outcome] += 1
        counts[:duplicates_expired] += result.duplicates_expired
      end

      counts
    end

    def reconcile_customer(customer, users, linked_users)
      identifier = customer["identifier"]
      user = user_for(customer, by_email: users, by_link: linked_users)
      email = external_email(customer)

      if user.nil?
        return skipped(:no_identifier) if email.blank?

        # A customer only exists once its owner has logged into pretix, so an
        # unrecognised one is normal, and writing nothing is the safe direction:
        # we cannot ask about a role whose holder we cannot find.
        return skipped(:no_user)
      end

      # Reached by email, not the stored link. Re-point only when the link is
      # absent or names a customer missing from this run's list altogether
      # (genuinely stale). Without the check, someone holding two pretix accounts
      # would be re-linked to whichever the loop reached second, every run.
      unless linked_users.key?(identifier)
        stored = user.pretix_customer_identifier
        remember_link(user, identifier) if stored.blank? || !linked_users.key?(stored)
      end

      # Fetched per customer, NOT sliced out of one list of every membership.
      # pretix pages them with no unique tiebreaker and no ordering parameter, so
      # LIMIT/OFFSET repeats and drops rows (live: 838 rows holding 626 distinct
      # ids, a customer's live membership among the missing). A member whose row
      # vanishes looks like one with none, and the reconcile would mint another
      # every night.
      apply(plan_for(entitled: entitled?(user), memberships: fetch_memberships(customer: identifier)),
            customer: identifier)
    end

    def skipped(outcome) = Result.new(outcome: outcome, duplicates_expired: 0)

    def fetch_memberships(customer: nil)
      @client.memberships(customer: customer, membership_type: Settings::MEMBERSHIP_TYPE_ID)
             .select { |membership| membership_type_id(membership) == Settings::MEMBERSHIP_TYPE_ID }
    end

    # The type comes back as an id or a nested object; filtering client-side too
    # means a widened server-side filter can never pull another type in.
    def membership_type_id(membership)
      value = membership["membership_type"]
      value.is_a?(Hash) ? value["id"].to_i : value.to_i
    end

    def apply(plan, customer:)
      return skipped(plan.outcome) unless plan.writes?

      guarded(customer) do
        if plan.creation
          @client.create_membership(customer: customer, membership_type: Settings::MEMBERSHIP_TYPE_ID,
                                    date_start: plan.creation.date_start, date_end: plan.creation.date_end)
        end
        plan.patches.each { |patch| @client.update_membership(patch.membership_id, date_end: patch.date_end) }

        Result.new(outcome: plan.outcome, duplicates_expired: plan.duplicate_patches.size)
      end
    end

    # AuthError aborts the run (fatal for every customer) rather than being
    # counted per customer. Suppressed writes (any non-production machine) are
    # expected and not reported.
    def guarded(context)
      yield
    rescue Client::WritesSuppressedError
      skipped(:suppressed)
    rescue Client::AuthError
      raise
    rescue Client::Error => e
      log_and_notify("Pretix membership sync failed for #{context}", e, context: { pretix_customer: context })
      skipped(:failed)
    end

    def blank_counts = OUTCOMES.index_with(0).merge(duplicates_expired: 0)

    def merge_counts(totals, counts)
      counts.to_h do |key, value|
        [ key, CUMULATIVE_COUNTS.include?(key) ? totals.fetch(key, 0) + value : value ]
      end
    end

    # Only called for an email match, so the stored link was blank or stale:
    # re-point it rather than costing that person two lookups forever. A link that
    # still resolves is never touched, which stops the people holding two pretix
    # accounts (an @sms.ed.ac.uk one and its rewritten @ed.ac.uk twin)
    # flip-flopping between them every run.
    def remember_link(user, identifier)
      return if identifier.blank? || user.pretix_customer_identifier == identifier

      user.update_column(:pretix_customer_identifier, identifier)
    rescue ActiveRecord::RecordNotUnique
      # Another user already claims this customer. Staying unlinked is the safe
      # direction: this one keeps matching by email, as before the column existed.
      nil
    end

    # An SSO account's email claim (external_identifier) wins where both exist:
    # it is the account the website drives. A native account has no
    # external_identifier, so its own email is the handle.
    def external_email(customer)
      normalize(customer["external_identifier"]).presence || normalize(customer["email"])
    end

    # The entitlement rule for both paths. Reads the loaded roles rather than
    # querying, so the reconcile can preload them for every customer at once.
    def entitled?(user)
      user.roles.any? { |role| ENTITLING_ROLES.include?(role.name.to_s.downcase.strip) }
    end

    # The stored link wins over the email, so a member who changed address
    # since their first login is still recognised.
    def user_for(customer, by_email:, by_link:)
      by_link[customer["identifier"]] || by_email[external_email(customer)]
    end

    # One query each, not one per customer.
    def users_by_email(customers)
      emails = customers.filter_map { |customer| external_email(customer) }.uniq
      return {} if emails.empty?

      # users.email is uniquely indexed, so one email resolves to one User.
      User.includes(:roles).where(email: emails).index_by { |user| normalize(user.email) }
    end

    def users_by_link(customers)
      identifiers = customers.filter_map { |customer| customer["identifier"].presence }
      return {} if identifiers.empty?

      User.includes(:roles)
          .where(pretix_customer_identifier: identifiers)
          .index_by(&:pretix_customer_identifier)
    end

    # Pure: facts in, plan out. No API, no ActiveRecord.
    def plan_for(entitled:, memberships:, now: Time.zone.now)
      dated, undated = memberships.partition { |membership| parse_time(membership["date_start"]) }
      # Undated rows are left alone: we cannot tell which window is widest, and
      # expiring the wrong one is the expensive mistake.
      return Plan.none(:ambiguous) if dated.empty? && undated.any?

      canonical = dated.min_by { |membership| [ parse_time(membership["date_start"]), membership["id"].to_i ] }
      duplicates = dated.reject { |membership| membership.equal?(canonical) }

      build_plan(entitled: entitled, canonical: canonical, duplicates: duplicates, now: now)
    end

    def build_plan(entitled:, canonical:, duplicates:, now:)
      duplicate_patches = duplicates.filter_map { |membership| expiry_patch(membership, now) }

      if entitled
        entitled_plan(canonical, duplicate_patches, now)
      else
        not_entitled_plan(canonical, duplicate_patches, now)
      end
    end

    def entitled_plan(canonical, duplicate_patches, now)
      target = self.class.membership_end(now)

      if canonical.nil?
        return Plan.new(outcome: :created, creation: Creation.new(date_start: membership_start(now), date_end: target),
                        canonical_patch: nil, duplicate_patches: duplicate_patches)
      end

      patch = extension_patch(canonical, target, now)
      Plan.new(outcome: outcome_for(patch, duplicate_patches, on_patch: :extended, on_duplicates: :deduplicated),
               creation: nil, canonical_patch: patch, duplicate_patches: duplicate_patches)
    end

    def not_entitled_plan(canonical, duplicate_patches, now)
      patch = canonical && expiry_patch(canonical, now)
      # A duplicate expired here is still a revocation, not housekeeping.
      Plan.new(outcome: outcome_for(patch, duplicate_patches, on_patch: :expired, on_duplicates: :expired),
               creation: nil, canonical_patch: patch, duplicate_patches: duplicate_patches)
    end

    def outcome_for(patch, duplicate_patches, on_patch:, on_duplicates:)
      return on_patch if patch
      return on_duplicates if duplicate_patches.any?

      :unchanged
    end

    # Nil unless date_end is nearer than REFRESH_WINDOW and differs from the
    # target. An unreadable date_end gets the refresh: writing the right date
    # can only widen an entitled member's window.
    def extension_patch(membership, target, now)
      current = parse_time(membership["date_end"])
      return if current && (current == target || current >= now + REFRESH_WINDOW)

      Patch.new(membership_id: membership["id"], date_end: target)
    end

    # Nil if it has already lapsed. pretix cannot delete a membership, so
    # revoking is a date change.
    def expiry_patch(membership, now)
      current = parse_time(membership["date_end"])
      return if current && current <= now

      Patch.new(membership_id: membership["id"], date_end: now)
    end

    # A new record starts today and never moves: everything bookable is in the
    # future, so a window that opened during a lapsed year grants nothing.
    def membership_start(now = Time.zone.now) = now.beginning_of_day

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return value.beginning_of_day if value.is_a?(Date)

      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError, TypeError
      nil
    end

    # Delegates to User's +normalizes :email+, which rewrites
    # sNNNNNNN@sms.ed.ac.uk to @ed.ac.uk. pretix keeps the email claim from FIRST
    # login and 30 live customers still carry the @sms form: downcasing alone
    # looked up an address no User has, so each was silently denied member
    # pricing (:no_user writes nothing, so it never complains).
    def normalize(email) = User.normalize_value_for(:email, email).presence
  end
end
