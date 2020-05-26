##
# Defines reports that may be downloaded in XLSX format, using axlsx.
##
class Admin::ReportsController < AdminController
  before_action :authorization

  # If you add a report, please also edit the reports helper to update the list of reports.

  ##
  # GET /admin/reports
  ##
  def index
    @title = 'Reports'
  end

  ##
  # A report containing a list of all users, and lists of users in each role.
  #
  # PUT /admin/reports/roles
  ##
  def roles
    report = RolesReport.new

    ReportsMailer.delay.send_report(current_user, report)

    redirect_to admin_reports_path, notice: 'The roles report will be emailed to you when it is ready.'
  end

  ##
  # A report containing a list of all members.
  ##
  def members
    report = MembershipReport.new

    ReportsMailer.delay.send_report(current_user, report)

    redirect_to admin_reports_path, notice: 'The members report will be emailed to you when it is ready.'
  end

  ##
  # A report containing all the entries in the NewsletterSubscriber model.
  ##
  def newsletter_subscribers
    report = NewsletterSubscribersReport.new

    ReportsMailer.delay.send_report(current_user, report)

    redirect_to admin_reports_path, notice: 'The subscribers report will be emailed to you when it is ready.'
  end

  ##
  # A report showing the number of shows a user has been in, and the number of staffing slots
  # they have completed.
  #
  # Broken into 6 month periods.
  #
  # Accepts two parameters:
  # * start_year The first year to include in the report (default - 1 year ago)
  # * end_year   The last year to include in the report (default - 1 year ahead)
  ##
  def staffing
    start_year = params[:first_year] || 1.years.ago.year
    end_year   = params[:end_year]   || 1.years.since.year

    report = StaffingReport.new(start_year, end_year)

    ReportsMailer.delay.send_report(current_user, report)

    redirect_to admin_reports_path, notice: 'The staffing report will be emailed to you when it is ready.'
  end

  private

  def authorization
    authorize! :read, 'reports'
  end
end
