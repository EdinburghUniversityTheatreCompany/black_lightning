##
# Operational alerts for the reimbursements portal (to the IT subcommittee).
class ReimbursementsMailer < ApplicationMailer
  DEFAULT_ALERT_EMAIL = "it@bedlamtheatre.co.uk".freeze

  def secret_expiry_warning(expires_on)
    @expires_on = expires_on
    @days_left = (expires_on - Date.current).to_i

    mail(to: alert_email,
         subject: "Reimbursements: Entra client secret expires in #{@days_left} days")
  end

  def auth_failure(detail)
    @detail = detail

    mail(to: alert_email,
         subject: "Reimbursements: mailbox authentication is failing")
  end

  private

  def alert_email
    Reimbursements::Settings.alert_email || DEFAULT_ALERT_EMAIL
  end
end
