# frozen_string_literal: true

namespace :pretix do
  desc "Report every write the membership reconcile WOULD make, without making any"
  task membership_reconcile_preview: :environment do
    unless Pretix::Settings.configured?
      abort "PRETIX_API_TOKEN is not set (or pretix: credentials are missing)."
    end

    client = Pretix::Client.new
    customers = client.customers
    memberships = client.memberships(membership_type: Pretix::Settings::MEMBERSHIP_TYPE_ID)
                        .group_by { |membership| membership["customer"] }

    # One query, roles preloaded, keyed exactly as the reconcile keys it.
    emails = customers.filter_map { |c| Pretix::MembershipSync.external_email(c) }.uniq
    users = User.includes(:roles).where(email: emails).index_by { |u| u.email.to_s.downcase }

    now = Time.zone.now
    counts = Hash.new(0)
    creates = []
    expiries = []
    extensions = []

    customers.each do |customer|
      email = Pretix::MembershipSync.external_email(customer)
      if email.blank?
        counts[:no_identifier] += 1
        next
      end

      user = users[email]
      if user.nil?
        counts[:no_user] += 1
        next
      end

      entitled = Pretix::MembershipSync.entitled?(user)
      mine = memberships[customer["identifier"]] || []
      plan = Pretix::MembershipSync.plan_for(entitled: entitled, memberships: mine, now: now)

      counts[plan.outcome] += 1
      label = "#{customer["identifier"]} #{email} (#{entitled ? "member" : "NOT a member"})"
      creates << label if plan.creation
      extensions << label if plan.canonical_patch && entitled
      expiries << "#{label} -> #{plan.patches.size} membership(s)" if plan.patches.any? && !entitled
    end

    puts "=" * 72
    puts "PRETIX MEMBERSHIP RECONCILE — PREVIEW ONLY, NOTHING WAS WRITTEN"
    puts "=" * 72
    puts "customers: #{customers.size}   type-225 memberships: #{memberships.values.sum(&:size)}"
    puts "website members (member / life member): #{users.values.count { |u| Pretix::MembershipSync.entitled?(u) }}"
    puts
    puts "OUTCOMES"
    counts.sort_by { |_, n| -n }.each { |outcome, n| puts "  #{outcome.to_s.ljust(16)} #{n}" }
    puts
    puts "WOULD CREATE a membership for #{creates.size} entitled member(s):"
    creates.first(20).each { |line| puts "  + #{line}" }
    puts "  ... and #{creates.size - 20} more" if creates.size > 20
    puts
    puts "WOULD REVOKE member pricing from #{expiries.size} customer(s) — check these carefully:"
    expiries.first(40).each { |line| puts "  - #{line}" }
    puts "  ... and #{expiries.size - 40} more" if expiries.size > 40
    puts
    puts "would extend/dedupe for #{extensions.size} entitled member(s) (no loss of access)"
    puts "=" * 72
    puts "Nothing was written. To apply, run the job: Pretix::ReconcileMembershipsJob.perform_now"
  end
end
