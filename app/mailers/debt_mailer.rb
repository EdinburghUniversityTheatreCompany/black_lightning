class DebtMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def mail_debtor(user, new_debtor)
    @user = user
    @new_debtor= new_debtor

    subject = new_debtor ? 'Notification of Debt' : 'Reminder of Debt'

    Admin::DebtNotification.create( user: @user,sent_on:Date.today,notification_type: :reminder)
    return mail(to: @user.email, subject: subject)
  end
end
