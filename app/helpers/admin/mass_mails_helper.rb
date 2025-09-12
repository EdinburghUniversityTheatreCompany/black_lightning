##
# Helper for mass mails.
##
module Admin::MassMailsHelper
  def get_send_date(mass_mail)
    if mass_mail.send_date.nil?
      "No Send Date"
    else
      l mass_mail.send_date, format: :longy
    end
  end

  def get_subject(mass_mail)
    mass_mail.subject.presence || "No Subject"
  end

  def get_sender_name(mass_mail)
    mass_mail.sender.try(&:name) || "No Sender"
  end
end
