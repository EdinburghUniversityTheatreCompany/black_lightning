# Please use deliver_now in rake tasks.
class Tasks::Logic::Debt
  def self.notify_debtors
    debtors = User.in_debt

    # Debtors who weren't in debt yesterday.
    new_debtors = debtors - User.in_debt(Date.today.advance(days: -1))
    new_debtors.each do |user|
      p "Notifying #{user.name_or_email} of debt"
      DebtMailer.mail_debtor(user, true).deliver_now
    end

    # Finds long time debtors after notifications have been added for all the new debtors.
    long_time_debtors = debtors - User.notified_since(Date.today.advance(days: -14))
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
