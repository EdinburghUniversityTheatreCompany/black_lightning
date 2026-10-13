class OpportunityMailer < ApplicationMailer
  def expiry_reminder(opportunity)
    @opportunity = opportunity
    @user = opportunity.creator

    mail(
      to: email_address_with_name(@user.email, @user.full_name),
      subject: "Your opportunity \"#{opportunity.display_title}\" expires in 3 days"
    )
  end

  # +note+ is an optional message from the reviewer.
  def approved(opportunity, note = nil) = decision(opportunity, note, "has been approved")

  def rejected(opportunity, note = nil) = decision(opportunity, note, "was not approved")

  private

  def decision(opportunity, note, outcome)
    @opportunity = opportunity
    @note = note.presence
    return if opportunity.notification_email.blank?

    mail(
      to: email_address_with_name(opportunity.notification_email, opportunity.notification_name),
      subject: "Your opportunity \"#{opportunity.display_title}\" #{outcome}"
    )
  end
end
