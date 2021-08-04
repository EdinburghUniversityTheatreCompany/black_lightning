class ComplaintsMailer < ApplicationMailer
  def new_complaint(complaint)
    @complaint = complaint

    @creation_time_string = l(@complaint.created_at, format: :longy)

    receiver = ['welfare@bedlamtheatre.co.uk', 'president@bedlamtheatre.co.uk']

    mail(to: receiver, subject: "New Complaint Submitted on #{@creation_time_string}")
  end
end
