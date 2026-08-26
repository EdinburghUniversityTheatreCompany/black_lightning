# frozen_string_literal: true

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
    lookup.prepare(customers.filter_map { |c| Pretix::MembershipSync.external_email(c) }.uniq)

    now = Time.zone.now
    seen = []
    counts = Hash.new(0)
    creates = []
    revokes = []
    extensions = []

    customers.each do |customer|
      email = Pretix::MembershipSync.external_email(customer)
      if email.blank?
        counts[:no_identifier] += 1
        next
      end

      status = lookup.status_for(email)
      if status.nil?
        # No User at all. The reconcile writes nothing here — this is the
        # safety bias, and it is why the preview must distinguish "unknown"
        # from "not a member" rather than collapsing the two into "expire".
        counts[:no_user] += 1
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

      label = "#{customer["identifier"]}  #{email}"
      creates << label if plan.creation
      extensions << label if plan.canonical_patch && status
      revokes << "#{label}  (#{plan.patches.size} membership(s))" if plan.patches.any? && !status
    end

    report(customers, seen.sum, lookup, counts, creates, revokes, extensions)
  end

  ##
  # Entitlement read from this app's own database.
  class DatabaseLookup
    def initialize = @users = {}

    def prepare(emails)
      @users = User.includes(:roles).where(email: emails).index_by { |user| user.email.to_s.downcase }
    end

    # nil = no such user (write nothing); true/false = entitled or not.
    def status_for(email)
      user = @users[email]
      return nil if user.nil?

      Pretix::MembershipSync.entitled?(user)
    end

    def entitled_count = @users.values.count { |user| Pretix::MembershipSync.entitled?(user) }
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

    def prepare(_emails) = nil
    def status_for(email) = @statuses[email]
    def entitled_count = @statuses.values.count(true)
    def source = "USERS_FILE (#{@statuses.size} users)"
  end

  def report(customers, membership_count, lookup, counts, creates, revokes, extensions)
    rule = "=" * 72
    puts rule
    puts "PRETIX MEMBERSHIP RECONCILE — PREVIEW ONLY, NOTHING WAS WRITTEN"
    puts rule
    puts "entitlement source: #{lookup.source}"
    puts "pretix customers: #{customers.size}   type-225 memberships read: #{membership_count}"
    puts "website members (member / life member): #{lookup.entitled_count}"
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
