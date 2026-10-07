class DailyMaintenanceJob < ApplicationJob
  queue_as :maintenance

  def perform
    Rails.logger.info "Starting daily maintenance job"

    step("notify_marketing_creatives") { Tasks::Logic::MarketingCreatives.notify_of_new_sign_ups }

    step("clean_up_personal_info") do
      Rails.logger.info "Cleaned up personal info for #{Tasks::Logic::Users.clean_up_personal_info} users"
    end

    step("purge_unattached_storage") do
      count = 0
      ActiveStorage::Blob.unattached.where("active_storage_blobs.created_at <= ?", 2.days.ago).find_each do |blob|
        blob.purge_later
        count += 1
      end
      Rails.logger.info "Queued #{count} unattached blobs for purging"
    end

    step("expire_outdated_debt") { Tasks::Logic::Debt.expire_outdated_debt }
    step("notify_debtors") { Tasks::Logic::Debt.notify_debtors }

    step("notify_expiring_opportunities") do
      # Only account holders get the reminder: an external submission has no creator.
      expiring = Opportunity.where(approved: true).where(expiry_date: Date.current + 3.days).where.not(creator_id: nil)
      expiring.each { |opp| OpportunityMailer.expiry_reminder(opp).deliver_later }
      Rails.logger.info "Queued expiry reminders for #{expiring.count} opportunities"
    end

    step("send_test_email") { TestMailer.test_email("m7IG49@report.hbchk.in").deliver_now }
    step("honeybadger_checkin") { Honeybadger.check_in("wqI0PL") }

    Rails.logger.info "Daily maintenance job completed successfully"
  end

  private

  def step(name)
    Honeybadger.context(current_step: name)
    Rails.logger.info "Daily maintenance: #{name}"
    yield
  end
end
