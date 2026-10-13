class OpportunityDigestJob < ApplicationJob
  queue_as :default

  def perform
    opportunities = Opportunity.awaiting_review.to_a
    return if opportunities.empty?

    User.with_role("Opportunity Reviewer").each do |user|
      OpportunityDigestMailer.digest(user, opportunities).deliver_later
    end
  end
end
