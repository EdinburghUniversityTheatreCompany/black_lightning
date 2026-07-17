##
# The daily budget-owner endorsement digest (see
# Reimbursements::OwnerEndorsementDigestJob). Sent through the website's own
# mailer, not the reimbursements Graph mailbox.
class OwnerEndorsementDigestMailer < ApplicationMailer
  def digest(user, expenses)
    @user = user
    @expenses = expenses

    mail(
      to: email_address_with_name(@user.email, @user.full_name),
      subject: "Reimbursement claims awaiting your budget sign-off"
    )
  end
end
