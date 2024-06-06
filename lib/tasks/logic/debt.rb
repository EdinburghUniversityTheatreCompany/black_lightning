# Please use deliver_now in rake tasks.
class Tasks::Logic::Debt
  # Removes all debts older than a year that have not already been completed some other way
  # or are currently awaiting 
  def self.expire_overdue_debt
    Admin::StaffingDebt.unfulfilled.where(due_by: ..(Date.current - 365.days)).update_all(state: 'expired')
    Admin::MaintenanceDebt.unfulfilled.where(due_by: ..(Date.current - 365.days)).update_all(state: 'expired')
  end

  def self.notify_debtors
    debtors = User.in_debt

    # Reallocate the debts for each debtors in case they do have enough 
    # staffing jobs/attendances to cover their debt, but something went wrong allocating previously.
    debtors.each do |debtor|
      debtor.reallocate_staffing_debts
      debtor.reallocate_maintenance_debts
    end

    # Reload debtors.
    debtors = User.in_debt

    # Debtors who weren't in debt yesterday.
    new_debtors = debtors - User.in_debt(Date.current.advance(days: -1))
    new_debtors.each do |user|
      p "Notifying #{user.name_or_email} of debt"
      DebtMailer.mail_debtor(user, true).deliver_now
    end

    # Finds long time debtors after notifications have been added for all the new debtors.
    long_time_debtors = debtors - User.notified_since(Date.current.advance(days: -14))
    long_time_debtors.each do |user|
      p "Reminding #{user.name_or_email} of debt"
      DebtMailer.mail_debtor(user, false).deliver_now
    end
  end

  def self.clear_all_debts
    Admin::MaintenanceDebt.destroy_all
    Admin::StaffingDebt.destroy_all
    Admin::DebtNotification.destroy_all
    Admin::Staffing.destroy_all
    Admin::StaffingJob.destroy_all
  end
end
