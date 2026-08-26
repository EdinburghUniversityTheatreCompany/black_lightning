# frozen_string_literal: true

require "csv"

namespace :pretix do
  desc "Report every write the membership reconcile WOULD make, without making any"
  task membership_reconcile_preview: :environment do
    unless Pretix::Settings.configured?
      abort "PRETIX_API_TOKEN is not set (or pretix: credentials are missing)."
    end

    # Entitlement normally comes from this database. USERS_FILE lets it come
    # from a TSV of "email<TAB>true|false" dumped elsewhere, so the preview can
    # be run against PRODUCTION's members from a machine that only has the
    # pretix token — no deploy needed to see what the first run would do.
    # Deliberately only the fact-gathering differs: the decision below is the
    # same Pretix::MembershipSync.plan_for the real reconcile calls, so a
    # preview cannot disagree with the run it is predicting.
    lookup = ENV["USERS_FILE"] ? FileLookup.new(ENV["USERS_FILE"]) : DatabaseLookup.new

    client = Pretix::Client.new
    customers = client.customers
    lookup.prepare(customers)

    # OUTPUT_CSV writes the full post-run roster: one row per customer, saying
    # whether they will hold a live type-225 membership once the reconcile has
    # run. pretix has no organizer-wide membership list in its control panel —
    # memberships are only visible one customer at a time — so this file is the
    # only way to see who ends up entitled.
    roster = ENV["OUTPUT_CSV"] ? [] : nil

    now = Time.zone.now
    seen = []
    counts = Hash.new(0)
    creates = []
    revokes = []
    extensions = []

    customers.each do |customer|
      # Resolve BEFORE looking at the email, in that order, because that is the
      # order the reconcile uses: a customer reached by its stored link is
      # recognised even when its email tells us nothing.
      status = lookup.status_for(customer)
      email = Pretix::MembershipSync.external_email(customer)

      if status.nil?
        # No User at all. The reconcile writes nothing either way — this is the
        # safety bias, and it is why the preview must distinguish "unknown" from
        # "not a member" rather than collapsing the two into "expire".
        counts[email.blank? ? :no_identifier : :no_user] += 1
        next
      end

      # Read per customer, exactly as the reconcile does. Slicing one whole-shop
      # membership list is what this preview did first, and it was wrong: pretix
      # pages that list with no unique tiebreaker, so it repeats and drops rows —
      # which inflated "would create" with people who already have a membership.
      # A preview that lies in the reassuring direction is worse than none.
      mine = client.memberships(customer: customer["identifier"],
                                membership_type: Pretix::Settings::MEMBERSHIP_TYPE_ID)
      seen << mine.size
      plan = Pretix::MembershipSync.plan_for(entitled: status, memberships: mine, now: now)
      counts[plan.outcome] += 1

      roster&.push(roster_row(customer, email, status, plan, mine, now))

      label = "#{customer["identifier"]}  #{email}"
      creates << label if plan.creation
      extensions << label if plan.canonical_patch && status
      revokes << "#{label}  (#{plan.patches.size} membership(s))" if plan.patches.any? && !status
    end

    write_roster(roster)
    report(customers, seen.sum, lookup, counts, creates, revokes, extensions)
  end

  # What this customer will hold once the reconcile has run. Derived from the
  # plan rather than re-deciding, so the file cannot disagree with the run.
  def roster_row(customer, email, entitled, plan, memberships, now)
    holds_live = memberships.any? { |m| Pretix::MembershipSync.parse_time(m["date_end"])&.> now }
    after = if plan.creation then true
    elsif !entitled then false
    else holds_live || plan.canonical_patch.present?
    end

    { identifier: customer["identifier"], email: email, member: entitled,
      action: plan.outcome, holds_membership_now: holds_live, holds_membership_after: after }
  end

  def write_roster(roster)
    return if roster.nil?

    path = ENV.fetch("OUTPUT_CSV")
    CSV.open(path, "w") do |csv|
      csv << roster.first.keys
      roster.each { |row| csv << row.values }
    end
    puts "roster of #{roster.size} customers written to #{path}"
    puts "  will hold a live membership after the run: #{roster.count { |r| r[:holds_membership_after] }}"
    puts
  end

  ##
  # Entitlement read from this app's own database.
  class DatabaseLookup
    def initialize
      @by_email = {}
      @by_link = {}
    end

    # Indexed exactly as the reconcile indexes them, and resolved through the
    # same Pretix::MembershipSync.user_for, so a preview cannot predict a
    # different run from the one that happens.
    def prepare(customers)
      @by_email = Pretix::MembershipSync.users_by_email(customers)
      @by_link = Pretix::MembershipSync.users_by_link(customers)
    end

    # nil = no such user (write nothing); true/false = entitled or not.
    def status_for(customer)
      user = Pretix::MembershipSync.user_for(customer, by_email: @by_email, by_link: @by_link)
      return nil if user.nil?

      Pretix::MembershipSync.entitled?(user)
    end

    def matched_entitled_count
      (@by_email.values | @by_link.values).count { |user| Pretix::MembershipSync.entitled?(user) }
    end

    # Every member on the website, whether or not they have a pretix account.
    # Counted through the roles rather than rolify's with_role so that it reads
    # the same case-insensitively-matched set the sync's entitlement rule does:
    # the production roles are named "Member" and "Life Member".
    def total_entitled_count
      role_ids = Role.where("LOWER(TRIM(name)) IN (?)", Pretix::MembershipSync::ENTITLING_ROLES).pluck(:id)
      return 0 if role_ids.empty?

      User.joins(:roles).where(roles: { id: role_ids }).distinct.count
    end

    def source = "this database"
  end

  ##
  # Entitlement read from a TSV dumped on another machine: "email\ttrue|false",
  # one line per user. A user missing from the file is treated as no user at
  # all, which is the direction that writes nothing.
  class FileLookup
    def initialize(path)
      @statuses = File.readlines(path).filter_map do |line|
        email, entitled = line.rstrip.split("\t", 2)
        normalized = User.normalize_value_for(:email, email).presence
        next if normalized.blank?

        [ normalized, entitled.to_s.strip.casecmp?("true") ]
      end.to_h
    end

    # Remembers which of the file's users a pretix customer actually resolved to,
    # so the two counts below mean the same things they do for DatabaseLookup.
    def prepare(customers)
      @matched_emails = customers.filter_map { |c| Pretix::MembershipSync.external_email(c) }.to_set
    end

    # Email only: a dump of "email<TAB>member" carries no User records, so the
    # stored links cannot be honoured here. The report says so rather than
    # letting this quietly diverge from a real run.
    def status_for(customer) = @statuses[Pretix::MembershipSync.external_email(customer)]

    def matched_entitled_count
      @statuses.count { |email, entitled| entitled && @matched_emails.include?(email) }
    end

    def total_entitled_count = @statuses.values.count(true)
    def source = "USERS_FILE (#{@statuses.size} users) — email only, stored links NOT honoured"
  end

  def report(customers, membership_count, lookup, counts, creates, revokes, extensions)
    rule = "=" * 72
    puts rule
    puts "PRETIX MEMBERSHIP RECONCILE — PREVIEW ONLY, NOTHING WAS WRITTEN"
    puts rule
    puts "entitlement source: #{lookup.source}"
    puts "pretix customers: #{customers.size}   type-225 memberships read: #{membership_count}"
    total = lookup.total_entitled_count
    matched = lookup.matched_entitled_count
    puts "website members (member / life member): #{total}"
    puts "  ...of whom have EVER logged into pretix: #{matched}"
    puts "  ...who therefore cannot be reached at all: #{total - matched} (they must log in once)"
    puts
    puts "OUTCOMES"
    counts.sort_by { |_, n| -n }.each { |outcome, n| puts "  #{outcome.to_s.ljust(16)} #{n}" }
    puts
    puts "WOULD CREATE a membership for #{creates.size} entitled member(s)"
    creates.first(15).each { |line| puts "  + #{line}" }
    puts "  ... and #{creates.size - 15} more" if creates.size > 15
    puts
    puts "WOULD REVOKE member pricing from #{revokes.size} customer(s) — READ THIS LIST"
    revokes.first(50).each { |line| puts "  - #{line}" }
    puts "  ... and #{revokes.size - 50} more" if revokes.size > 50
    puts
    puts "would extend/dedupe for #{extensions.size} entitled member(s) — no loss of access"
    puts rule
    puts "Nothing was written."
  end
end
