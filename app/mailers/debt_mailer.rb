class DebtMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def new_debtor(user)
    @user = user

    Admin::DebtNotification.create(user:@user, sent_on:Date.today,notification_type: :initial_notification)
    mail(to: @user.email, subject: 'Notification of Debt')
  end

  def unrepentant_debtor(user)
    @user = user

    Admin::DebtNotification.create(user:@user, sent_on:Date.today,notification_type: :reminder)
    mail(to: @user.email, subject: 'Reminder of Debt')
  end
end
