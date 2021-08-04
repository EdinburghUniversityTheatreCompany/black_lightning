# Not directly tested, but the debt task is, so it is covered.
class DebtMailer < ApplicationMailer
  default reply_to: 'FOH and Theatre Manager <debt@bedlamtheatre.co.uk>'

  def mail_debtor(user, new_debtor)
    @user = user
    @new_debtor = new_debtor

    @subject = new_debtor ? 'Notification of Debt' : 'Reminder of Debt'
    notification_type = new_debtor ? :initial_notification : :reminder

    @debt_moment = Admin::Debt.users_oldest_debt(@user.id) || '|||ERROR: No moment of debt found. Please email it@bedlamtheatre.co.uk|||'

    Admin::DebtNotification.create(user: @user, sent_on: Date.today, notification_type: notification_type)
    return mail(to: @user.email, subject: @subject)
  end
end
