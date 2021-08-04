class ComplaintsMailer < ApplicationMailer
  def new_complaint(complaint)
    @complaint = complaint

    @creation_time_string = l(@complaint.created_at, format: :longy)

    receiver = ['welfare@bedlamtheatre.co.uk', 'president@bedlamtheatre.co.uk']

    @subject = "New Complaint Submitted on #{@creation_time_string}"

    mail(to: receiver, subject: @subject)
  end
end
