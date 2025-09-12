class StaffingMailer < ApplicationMailer
  def staffing_reminder(job)
    @staffing = job.staffable
    @user = job.user

    return if @user.nil?

    @start_time = l @staffing.start_time, format: :long
    @subject = "Bedlam Theatre Staffing at #{@start_time}"

    duty_manager = @staffing.staffing_jobs.where(name: "duty manager").or(@staffing.staffing_jobs.where(name: "dm")).first&.user&.full_name
    committee_rep = @staffing.staffing_jobs.where(name: "committee rep").first&.user&.full_name

    if duty_manager.present? && committee_rep.present?
      @late_running_sentence = ", or let the Duty Manager (#{duty_manager}) or Committee Rep (#{committee_rep}) know if you run late"
    elsif duty_manager.present?
      @late_running_sentence = ", or let the Duty Manager (#{duty_manager}) know if you run late"
    elsif committee_rep.present?
      @late_running_sentence = ", or let the Committee Rep (#{committee_rep}) know if you run late"
    else
      @late_running_sentence = ""
    end

    mail(to: email_address_with_name(@user.email, @user.full_name), subject: @subject)
  end
end
