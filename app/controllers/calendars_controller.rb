class CalendarsController < ApplicationController
  # Token-authenticated public endpoint — no Devise session required for feed
  skip_authorization_check
  skip_before_action :require_profile_completion!, only: [ :staffing ]

  before_action :authenticate_user!, only: [ :regenerate_token ]

  def staffing
    user = User.find_by!(calendar_token: params[:token])
    jobs = user.staffing_jobs
               .joins("INNER JOIN admin_staffings ON admin_staffings.id = admin_staffing_jobs.staffable_id
                       AND admin_staffing_jobs.staffable_type = 'Admin::Staffing'")
               .where("admin_staffings.end_time >= ?", Time.current)
               .includes(:staffable)

    last_modified = jobs.flat_map { |j| [ j.updated_at, j.staffable.updated_at ] }.max || Time.current

    if stale?(etag: last_modified.to_i, last_modified: last_modified, public: false)
      cal = build_feed(jobs)
      response.headers["Content-Disposition"] = 'attachment; filename="staffing.ics"'
      render plain: cal.to_ical, content_type: "text/calendar"
    end
  end

  def regenerate_token
    current_user.regenerate_calendar_token
    redirect_to admin_staffings_path, notice: "Your calendar link has been regenerated."
  end

  private

  def build_feed(jobs)
    require "icalendar"

    cal = Icalendar::Calendar.new
    cal.prodid = "-//Bedlam Theatre//BlackLightning//EN"
    cal.append_custom_property("X-PUBLISHED-TTL", "PT1H")
    cal.append_custom_property("REFRESH-INTERVAL;VALUE=DURATION", "PT1H")

    jobs.each do |job|
      cal.add_event(job.to_ical_event)
    end

    cal
  end
end
