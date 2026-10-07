# Please use deliver_now in rake tasks.
class Tasks::Logic::Debt
  # Removes all debts older than a year that have not already been completed some other way
  # or are currently awaiting
  def self.expire_outdated_debt
    Admin::StaffingDebt.unfulfilled.where(due_by: ..(Date.current - 365.days)).update_all(state: "expired")
    Admin::MaintenanceDebt.unfulfilled.where(due_by: ..(Date.current - 365.days)).update_all(state: "expired")
  end

  def self.notify_debtors
    debtors = User.in_debt.includes(:admin_maintenance_debts, :admin_staffing_debts)

    # Reallocate the debts for each debtors in case they do have enough
    # staffing jobs/attendances to cover their debt, but something went wrong allocating previously.
    debtors.each do |debtor|
      debtor.reallocate_staffing_debts
      debtor.reallocate_maintenance_debts
    end

    # Reload debtors.
    debtors = User.in_debt.includes(:admin_maintenance_debts, :admin_staffing_debts)

    # Debtors who weren't in debt yesterday.
    new_debtors = debtors - User.in_debt(Date.current.advance(days: -1))
    failures = new_debtors.count { |user| !deliver_debt_mail(user, true) }

    # Finds long time debtors after notifications have been added for all the new debtors.
    long_time_debtors = debtors - User.notified_since(Date.current.advance(days: -14))
    failures += long_time_debtors.count { |user| !deliver_debt_mail(user, false) }

    if failures.positive?
      Rails.logger.warn "Debt notification summary: #{failures} email(s) failed to deliver out of #{new_debtors.size + long_time_debtors.size} total attempts"
    end
  end

  # True when sent, false when SMTP refused it (logged), so one bad address can't stop the rest.
  def self.deliver_debt_mail(user, initial)
    Rails.logger.info "#{initial ? 'Notifying' : 'Reminding'} #{user.name_or_email} of debt"
    DebtMailer.mail_debtor(user, initial).deliver_now
    true
  rescue Net::SMTPError => e
    Rails.logger.error "Failed to send debt #{initial ? 'notification' : 'reminder'} to #{user.name_or_email} (ID: #{user.id}): #{e.class} - #{e.message}"
    false
  end
  private_class_method :deliver_debt_mail

  def self.clear_all_debts
    Admin::MaintenanceDebt.destroy_all
    Admin::StaffingDebt.destroy_all
    Admin::DebtNotification.destroy_all
    Admin::Staffing.destroy_all
    Admin::StaffingJob.destroy_all
  end
end
