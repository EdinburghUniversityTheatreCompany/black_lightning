class OpportunityDigestJob < ApplicationJob
  queue_as :default

  def perform
    opportunities = Opportunity.where(approved: false).where("expiry_date > ?", Date.current)

    return if opportunities.none?

    reviewers = Role.find_by(name: "Opportunity Reviewer")&.users || []

    reviewers.each do |user|
      OpportunityDigestMailer.digest(user, opportunities).deliver_later
    end
  end
end
