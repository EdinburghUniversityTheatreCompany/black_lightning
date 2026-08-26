# frozen_string_literal: true

module Pretix
  ##
  # Drives each pretix customer's ONE membership from the website's +member+ /
  # +life member+ roles. See docs/pretix/membership-sync.md.
  #
  # Everything a person's membership should be is decided by the single pure
  # function +plan_for+, and every write is made by the single +apply+. The
  # per-user sync (login, role change) and the nightly reconcile differ ONLY in
  # how they gather the facts — entitlement and the existing membership rows —
  # so the two can never drift into disagreeing about what a person should have.
  # (Same convention as Reimbursements::Exports, where one #row feeds both the
  # CSV and the workbook.)
  #
  #   sync_user(user)  => Symbol, one of OUTCOMES
  #   reconcile_all    => Hash of counts, one key per outcome
  #
  # SAFETY BIAS: getting "not entitled" wrong revokes a real person's member
  # pricing, while getting it wrong the other way costs a discounted seat. So
  # every ambiguity here resolves towards leaving a membership alone: a customer
  # we cannot match to a User, one carrying no SSO identity, and a membership
  # whose dates will not parse all produce NO write at all. Only a customer that
  # resolves to a User who demonstrably lacks the role is ever expired.
  class MembershipSync
    include ErrorReporting

    # Either role entitles. Compared downcased, as Role::NON_PURGEABLE_ROLES does.
    ENTITLING_ROLES = [ "member", "life member" ].freeze

    # Slack past the end of the academic year, for the manual September rollover.
    GRACE = 3.weeks

    # Only refresh date_end once it is nearer than this, so a nightly run over
    # an already-correct shop writes nothing.
    REFRESH_WINDOW = 18.months

    # Memberships are read per customer precisely so a pass cannot miss rows
    # (see reconcile_customer), but the CUSTOMER list is paged and pretix pages
    # it without a unique tiebreaker too. Re-fetch and repeat until a pass finds
    # nothing to do; the cap stops a bug from looping forever.
    MAX_PASSES = 5

    OUTCOMES = %i[
      created extended expired deduplicated unchanged
      no_customer no_identifier no_user ambiguous suppressed failed
    ].freeze

    # Counts that accumulate across reconcile passes (writes actually made);
    # every other count is a snapshot of the final pass.
    CUMULATIVE_COUNTS = %i[created extended expired deduplicated duplicates_expired].freeze

    Patch = Data.define(:membership_id, :date_end)
    Creation = Data.define(:date_start, :date_end)

    ##
    # What one customer needs: at most one creation, at most one patch of the
    # canonical record, and a patch per duplicate being collapsed.
    Plan = Data.define(:outcome, :creation, :canonical_patch, :duplicate_patches) do
      def self.none(outcome) = new(outcome: outcome, creation: nil, canonical_patch: nil, duplicate_patches: [])

      def patches = [ canonical_patch, *duplicate_patches ].compact

      def writes? = creation.present? || patches.any?
    end

    Result = Data.define(:outcome, :duplicates_expired)

    def initialize(client: Pretix::Client.new)
      @client = client
    end

    # One user, straight after a login or a role change. The nightly reconcile
    # is what actually guarantees correctness; this only makes it feel immediate.
    def sync_user(user)
      return :no_customer if user.blank? || user.email.blank?

      guarded(user.email) do
        linked = @client.customer(user.pretix_customer_identifier)
        customer = linked.presence || @client.customer_by_email(user.email)
        next skipped(:no_customer) if customer.blank?
        # Only enforced when we found them by email. A customer reached through
        # the stored link IS this person by construction — that is the whole
        # point of storing it — and demanding the emails still agree would undo
        # the link the moment someone changed address, which is the case it
        # exists for.
        if linked.blank? && external_email(customer) != normalize(user.email)
          next skipped(:no_identifier)
        end

        identifier = customer["identifier"]
        # Reached by email, so the stored link was either absent or no longer
        # resolves. Either way this is the customer to point at from now on.
        remember_link(user, identifier) if linked.blank?
        apply(plan_for(entitled: entitled?(user), memberships: fetch_memberships(customer: identifier)),
              customer: identifier)
      end.outcome
    end

    # The whole shop. One customer list per pass, then one membership read per
    # customer that resolves to a User — see reconcile_customer for why the
    # memberships cannot come from a single list call.
    #
    # A failure on the customer list is deliberately NOT caught: it is fatal for
    # every customer alike, and a run that carried on would report a shop full of
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

    # Called only when the customer was reached by EMAIL, which means the stored
    # link was blank or no longer resolves — so a stale link is re-pointed rather
    # than leaving that person paying two lookups forever. A link that still
    # resolves is never touched, which is what stops the handful of people
    # holding two pretix accounts (an @sms.ed.ac.uk one and its rewritten
    # @ed.ac.uk twin) flip-flopping between them on every run.
    def remember_link(user, identifier)
      return if identifier.blank? || user.pretix_customer_identifier == identifier

      user.update_column(:pretix_customer_identifier, identifier)
    rescue ActiveRecord::RecordNotUnique
      # Another user already claims this customer. Leaving this one unlinked is
      # the safe direction: it keeps matching by email, exactly as it did before
      # this column existed.
      nil
    end

    public

    class << self
      # The address this customer is matched to a User by.
      #
      # An SSO account is keyed on the email claim, held in external_identifier,
      # and that is preferred wherever it exists. A NATIVE account (someone who
      # signed up in the shop with a password) has no external_identifier at all,
      # and for those the account's own email is the only handle there is — and a
      # perfectly good one, since the reconcile will look them up the same way
      # next time. Members should not have to have used SSO to be recognised.
      #
      # The preference matters where both exist for one address: the SSO account
      # is the one the website drives, so it wins.
      def external_email(customer)
        normalize(customer["external_identifier"]).presence || normalize(customer["email"])
      end

      # True for a customer pretix created from an SSO login.
      def sso?(customer) = normalize(customer["external_identifier"]).present?

      # THE entitlement rule, for both paths. Reads the loaded roles rather than
      # querying, so the reconcile can preload them for every customer at once
      # and still ask exactly the same question the single-user path asks.
      def entitled?(user)
        return false if user.blank?

        user.roles.any? { |role| ENTITLING_ROLES.include?(role.name.to_s.downcase.strip) }
      end

      # THE resolution, as plan_for is THE decision. The nightly reconcile and
      # the dry-run preview both go through it, so a preview cannot predict a
      # different run from the one that happens — which it silently did once the
      # stored link arrived and only the reconcile knew about it.
      def user_for(customer, by_email:, by_link:)
        by_link[customer["identifier"]] || by_email[external_email(customer)]
      end

      # One query each, so neither caller looks a user up per customer.
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

      # THE decision. Pure — no API, no ActiveRecord — so both callers reach it
      # with nothing but facts, and it is unit-testable on its own.
      def plan_for(entitled:, memberships:, now: Time.zone.now)
        dated, undated = memberships.partition { |membership| parse_time(membership["date_start"]) }
        # Undated rows are left strictly alone: we cannot tell which window is
        # widest, and expiring the wrong one is the expensive mistake.
        return Plan.none(:ambiguous) if dated.empty? && undated.any?

        canonical = dated.min_by { |membership| [ parse_time(membership["date_start"]), membership["id"].to_i ] }
        duplicates = dated.reject { |membership| membership.equal?(canonical) }

        build_plan(entitled: entitled, canonical: canonical, duplicates: duplicates, now: now)
      end

      # End of the NEXT academic year plus three weeks, end of day: far enough
      # ahead that nothing on sale is ever outside the window (pretix validates a
      # membership against the SHOW's date, not the purchase date), and near
      # enough that the membership expires by itself within two years if this
      # sync dies. From Aug 2026 that is 2027-09-21T23:59:59+01:00.
      def membership_end(now = Time.zone.now)
        start_year = ApplicationController.helpers.date_to_academic_year(now.to_date)
        (Date.new(start_year + 2, 8, 31) + GRACE).end_of_day.change(usec: 0)
      end

      # A new record starts today. It never moves afterwards: everything
      # bookable is in the future, so a window that opened during a lapsed year
      # cannot grant anything.
      def membership_start(now = Time.zone.now) = now.beginning_of_day

      def parse_time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return value.beginning_of_day if value.is_a?(Date)

        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError, TypeError
        nil
      end

      # Delegates to User's own +normalizes :email+ rather than restating it.
      # That rule rewrites sNNNNNNN@sms.ed.ac.uk to @ed.ac.uk, and pretix stores
      # whatever the email claim said at FIRST login — 30 live customers still
      # carry the @sms form. Merely downcasing here looked them up under an
      # address no User has, so each resolved to :no_user and was silently
      # denied member pricing forever, in the direction that writes nothing and
      # therefore never complains.
      def normalize(email) = User.normalize_value_for(:email, email).presence

      private

      def build_plan(entitled:, canonical:, duplicates:, now:)
        duplicate_patches = duplicates.filter_map { |membership| expiry_patch(membership, now) }

        if entitled
          entitled_plan(canonical, duplicate_patches, now)
        else
          not_entitled_plan(canonical, duplicate_patches, now)
        end
      end

      def entitled_plan(canonical, duplicate_patches, now)
        target = membership_end(now)

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

      # Nil unless date_end is both nearer than REFRESH_WINDOW and actually
      # different from the target. The window alone would re-write the same
      # value every night for the half of the year the horizon sits inside it.
      # An unreadable date_end counts as needing the refresh: writing the right
      # end date can only widen an entitled member's window.
      def extension_patch(membership, target, now)
        current = parse_time(membership["date_end"])
        return if current && (current == target || current >= now + REFRESH_WINDOW)

        Patch.new(membership_id: membership["id"], date_end: target)
      end

      # Nil if it has already lapsed — pretix cannot delete a membership, so
      # revoking is a date change, and a date already in the past needs none.
      def expiry_patch(membership, now)
        current = parse_time(membership["date_end"])
        return if current && current <= now

        Patch.new(membership_id: membership["id"], date_end: now)
      end
    end

    delegate :entitled?, :plan_for, :external_email, :normalize,
             :user_for, :users_by_email, :users_by_link, to: :class

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
      # The stored link wins over the email, so a member who has changed address
      # since their first login is still recognised.
      user = user_for(customer, by_email: users, by_link: linked_users)
      email = external_email(customer)

      if user.nil?
        return skipped(:no_identifier) if email.blank?

        # A customer only exists once its owner has logged into pretix, so an
        # unrecognised one is normal rather than an error — and writing nothing
        # for it is also the safe direction, since we cannot ask about a role we
        # cannot find the holder of.
        return skipped(:no_user)
      end

      # Reached by email rather than by the stored link. Re-point that link only
      # when it is absent or names a customer not in this run's list at all —
      # i.e. genuinely stale. Without the check, someone holding two pretix
      # accounts would be re-linked to whichever the loop reached second, every
      # single run.
      unless linked_users.key?(identifier)
        stored = user.pretix_customer_identifier
        remember_link(user, identifier) if stored.blank? || !linked_users.key?(stored)
      end

      # Fetched per customer, NOT sliced out of one list of every membership.
      # pretix orders memberships by -date_end, -date_start, membership_type with
      # no unique tiebreaker and offers no ordering parameter, so paging the full
      # list under LIMIT/OFFSET silently repeats some rows and drops others —
      # measured against the live shop as 838 rows containing only 626 distinct
      # ids, with three of one customer's ten memberships missing, including
      # their live one. A member whose only membership went missing would look
      # like a member with none, so the reconcile would mint another every single
      # night. This costs one request per customer and is the only way to be sure
      # we have all of somebody's rows.
      apply(plan_for(entitled: entitled?(user), memberships: fetch_memberships(customer: identifier)),
            customer: identifier)
    end

    def skipped(outcome) = Result.new(outcome: outcome, duplicates_expired: 0)

    # One query for every customer we might touch, roles preloaded, so the
    # entitlement rule can be the same one sync_user uses.


    def fetch_memberships(customer: nil)
      @client.memberships(customer: customer, membership_type: Settings::MEMBERSHIP_TYPE_ID)
             .select { |membership| membership_type_id(membership) == Settings::MEMBERSHIP_TYPE_ID }
    end

    # The type comes back as an id, or as a nested object depending on the
    # endpoint; filtering client-side as well means a widened server-side filter
    # can never drag someone else's membership type into the sync.
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

    # AuthError is fatal for every customer alike, so it aborts rather than
    # being counted 875 times. Suppressed writes (any non-production machine)
    # are expected and not worth reporting.
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
  end
end
