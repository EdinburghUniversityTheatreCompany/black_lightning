class ReportsMailer < ActionMailer::Base
  default from: "Bedlam Theatre <no-reply@bedlamtheatre.co.uk>"

  def send_report(user, report)
    @user = user

    report = report.create

    @errors = report.validate

    attachments['report.xlsx'] = report.to_stream.read

    mail(:to => @user.email, :subject => "Bedlam Theatre Report")
  end
end
