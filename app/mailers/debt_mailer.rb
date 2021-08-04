# Not directly tested, but the debt task is, so it is covered.
class DebtMailer < ApplicationMailer
  def mail_debtor(user, new_debtor)
    @user = user
    @new_debtor = new_debtor

    subject = new_debtor ? 'Notification of Debt' : 'Reminder of Debt'
    notification_type = new_debtor ? :initial_notification : :reminder

    Admin::DebtNotification.create(user: @user, sent_on: Date.today, notification_type: notification_type)
    return mail(to: @user.email, subject: subject)
  end
end
