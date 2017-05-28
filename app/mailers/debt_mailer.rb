class DebtMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def new_debtor(user)
    @user = user

    mail(to: @user.email, subject: 'Notification of Debt')
    Admin::DebtNotification.create(user:@user, sent_on:Date.today)
  end

  def unrepentant_debtor(user)
    @user = user

    mail(to: @user.email, subject: 'Reminder of Debt')
    Admin::DebtNotification.create(user:@user, sent_on:Date.today)
  end
end
