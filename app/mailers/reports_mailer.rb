class ReportsMailer < ApplicationMailer
  default reply_to: "IT <it@bedlamtheatre.co.uk>"

  def send_report(user, report_class_name, *report_args)
    @user = user

    # Instantiate the report class with any arguments
    report_class = report_class_name.constantize
    report_instance = report_args.any? ? report_class.new(*report_args) : report_class.new

    report = report_instance.create

    @errors = report.validate

    attachments["report.xlsx"] = report.to_stream.read

    @subject = "Bedlam Theatre Report"

    mail(to: email_address_with_name(@user.email, @user.full_name), subject: @subject)
  end
end
