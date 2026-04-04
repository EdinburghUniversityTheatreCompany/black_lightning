class StaffingMailer < ApplicationMailer
  ##
  # Sends a calendar invite (.ics attachment) for a staffing job.
  # method: :request for new/updated invite, :cancel for cancellation.
  # recipient: defaults to job.user; pass explicitly when removing a user.
  ##
  def calendar_invite(job, method:, recipient: nil)
    @job      = job
    @staffing = job.staffable
    @user     = recipient || job.user
    @method   = method

    ics_data = job.ical_calendar(method: method).to_ical

    attachments["staffing.ics"] = {
      mime_type: "text/calendar; charset=utf-8; method=#{method.to_s.upcase}",
      content:   ics_data
    }

    mail(
      to:      email_address_with_name(@user.email, @user.full_name),
      subject: calendar_invite_subject
    )
  end

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

  private

  def calendar_invite_subject
    show = @staffing.show_title
    start_time = l @staffing.start_time, format: :long

    if @method == :cancel
      "Staffing removed: #{show} on #{start_time}"
    else
      "Staffing confirmed: #{show} on #{start_time} (#{@job.name})"
    end
  end
end
