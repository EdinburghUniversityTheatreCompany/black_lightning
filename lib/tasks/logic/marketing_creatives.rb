class Tasks::Logic::MarketingCreatives
  def self.notify_of_new_sign_ups
    datetime_range = DateTime.now.advance(hours: -25)..DateTime.now
    new_sign_ups = MarketingCreatives::Profile.where(approved: [false, nil]).where(created_at: datetime_range)

    if new_sign_ups.any?
      MarketingCreativesMailer.notify_of_new_sign_ups(new_sign_ups).deliver_now
      p "Notified the Marketing Manager of #{new_sign_ups.count} new sign-ups."
    end
  end
end
