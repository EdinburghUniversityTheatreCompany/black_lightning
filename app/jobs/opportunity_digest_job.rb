class OpportunityDigestJob < ApplicationJob
  queue_as :default

  def perform
    opportunities = Opportunity.where(approved: false).where("expiry_date > ?", Date.current)

    return if opportunities.none?

    reviewers = User.in_group("Opportunity Reviewer") || []

    opportunities_list = opportunities.to_a
    reviewers.each do |user|
      OpportunityDigestMailer.digest(user, opportunities_list).deliver_later
    end
  end
end
