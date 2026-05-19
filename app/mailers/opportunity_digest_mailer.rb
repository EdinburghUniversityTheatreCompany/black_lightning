class OpportunityDigestMailer < ApplicationMailer
  def digest(user, opportunities)
    @user = user
    @opportunities = opportunities

    mail(
      to: email_address_with_name(@user.email, @user.full_name),
      subject: "Opportunities awaiting review"
    )
  end
end
