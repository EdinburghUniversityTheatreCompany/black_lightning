class ComplaintsMailerPreview < ActionMailer::Preview
  def new_complaint
    complaint = FactoryBot.create(:complaint)

    ComplaintsMailer.new_complaint(complaint)
  end
end
