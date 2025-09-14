class DailyMaintenanceJob < ApplicationJob
  queue_as :maintenance

  def perform
    Rails.logger.info "Starting daily maintenance job"

    notify_marketing_creatives
    clean_up_personal_info
    purge_unattached_storage
    expire_outdated_debt
    notify_debtors
    honeybadger_checkin

    Rails.logger.info "Daily maintenance job completed successfully"
  end

  private

  def notify_marketing_creatives
    Rails.logger.info "Notifying marketing manager of new sign-ups"
    Tasks::Logic::MarketingCreatives.notify_of_new_sign_ups
  end

  def clean_up_personal_info
    Rails.logger.info "Cleaning up personal info per privacy policy"
    count = Tasks::Logic::Users.clean_up_personal_info
    Rails.logger.info "Cleaned up personal info for #{count} users"
  end

  def purge_unattached_storage
    Rails.logger.info "Purging unattached Active Storage blobs"
    blob_count = 0
    ActiveStorage::Blob.unattached.where("active_storage_blobs.created_at <= ?", 2.days.ago).find_each do |blob|
      blob.purge_later
      blob_count += 1
    end
    Rails.logger.info "Queued #{blob_count} unattached blobs for purging"
  end

  def expire_outdated_debt
    Rails.logger.info "Expiring outdated debt"
    Tasks::Logic::Debt.expire_outdated_debt
  end

  def notify_debtors
    Rails.logger.info "Notifying debtors"
    Tasks::Logic::Debt.notify_debtors
  end

  def honeybadger_checkin
    Rails.logger.info "Sending Honeybadger check-in"
    Honeybadger.check_in("wqI0PL")
  end
end
