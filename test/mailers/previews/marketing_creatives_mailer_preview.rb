class MarketingCreativesMailerPreview < ActionMailer::Preview
  def notify_of_of_new_sign_ups
    new_sign_ups = MarketingCreatives::Profile.all.sample(5)

    MarketingCreativesMailer.notify_of_new_sign_ups(new_sign_ups)
  end
end
