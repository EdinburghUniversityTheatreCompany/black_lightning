class ReportsMailer < ApplicationMailer
  default reply_to: 'IT <it@bedlamtheatre.co.uk>'

  def send_report(user, report)
    @user = user

    report = report.create

    @errors = report.validate

    attachments['report.xlsx'] = report.to_stream.read

    @subject = 'Bedlam Theatre Report'

    mail(to: @user.email, subject: @subject)
  end
end
