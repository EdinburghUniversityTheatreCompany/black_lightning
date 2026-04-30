##
# Helper for reports.
##
module Admin::ReportsHelper
  ##
  # Defines all existing reports Admin::ReportsController.
  ##
  def list_reports
    # action: name
    {
      roles: "Roles",
      members: "Members",
      newsletter_subscribers: "Newsletter Subscribers",
      staffing: "Staffing"
    }
  end

  def get_report_link(report, report_name)
    get_link("reports", report,
      link_text: report_name,
      link_target: url_for([ :admin_reports, report ]),
      http_method: :put,
      condition: current_ability.can?(:read, "reports"))
  end
end
