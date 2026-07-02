class OpportunityMailer < ApplicationMailer
  def expiry_reminder(opportunity)
    @opportunity = opportunity
    @user = opportunity.creator

    mail(
      to: email_address_with_name(@user.email, @user.full_name),
      subject: "Your opportunity \"#{opportunity.title}\" expires in 3 days"
    )
  end

  # Sent to the submitter when their opportunity is approved. +note+ is an optional message
  # from the reviewer.
  def approved(opportunity, note = nil)
    @opportunity = opportunity
    @note = note.presence
    return if opportunity.notification_email.blank?

    mail(
      to: notification_recipient(opportunity),
      subject: "Your opportunity \"#{opportunity.display_title}\" has been approved"
    )
  end

  # Sent to the submitter when their opportunity is rejected. +note+ is an optional message.
  def rejected(opportunity, note = nil)
    @opportunity = opportunity
    @note = note.presence
    return if opportunity.notification_email.blank?

    mail(
      to: notification_recipient(opportunity),
      subject: "Your opportunity \"#{opportunity.display_title}\" was not approved"
    )
  end

  private

  def notification_recipient(opportunity)
    name = opportunity.notification_name
    email_address_with_name(opportunity.notification_email, name.presence || opportunity.notification_email)
  end
end
