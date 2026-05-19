class OpportunityMailer < ApplicationMailer
  def expiry_reminder(opportunity)
    @opportunity = opportunity
    @user = opportunity.creator

    mail(
      to: email_address_with_name(@user.email, @user.full_name),
      subject: "Your opportunity \"#{opportunity.title}\" expires in 3 days"
    )
  end
end
