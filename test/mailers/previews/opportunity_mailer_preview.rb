class OpportunityMailerPreview < ActionMailer::Preview
  def expiry_reminder
    OpportunityMailer.expiry_reminder(Opportunity.active.first || Opportunity.first)
  end

  def approved
    OpportunityMailer.approved(sample_opportunity, "Thanks — this looks great, it's now live.")
  end

  def rejected
    OpportunityMailer.rejected(sample_opportunity, "We can't post this one as it falls outside our remit.")
  end

  private

  def sample_opportunity
    Opportunity.where.not(submitter_email: nil).first || Opportunity.first
  end
end
