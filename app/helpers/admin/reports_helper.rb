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
    link_to report_name, url_for([ :admin_reports, report ]), method: :put
  end
end
