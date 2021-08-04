class ReportsMailerPreview < ActionMailer::Preview
  def send_report
    report = Reports::NewsletterSubscribers.new
    user = User.all.sample

    ReportsMailer.send_report(user, report)
  end
end
