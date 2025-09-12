# Not directly tested, but the marketing creatives mail task is, so it is covered.
class MarketingCreativesMailer < ApplicationMailer
  default reply_to: "IT <it@bedlamtheatre.co.uk>"

  def notify_of_new_sign_ups(new_sign_ups)
    recipients = "marketing@bedlamtheatre.co.uk"

    @subject = "#{new_sign_ups.count} new sign-ups for Marketing Creative Profiles"

    @new_sign_ups = new_sign_ups

    mail(to: recipients, subject: @subject)
  end
end
