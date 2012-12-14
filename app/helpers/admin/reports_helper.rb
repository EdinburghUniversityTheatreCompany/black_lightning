##
# Helper for reports.
##
module Admin::ReportsHelper
  ##
  # Retrieves a list of all reports defined in Admin::ReportsController.
  ##
  def list_reports
    reports = Admin::ReportsController.action_methods
    reports = reports.map { |r| r.to_s }
    reports.delete('index')
    reports.delete('authorize_backend!')
    reports.delete('set_globals')
    reports.delete('report_500')

    return reports
  end
end
