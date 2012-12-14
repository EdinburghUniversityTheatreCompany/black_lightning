##
# Defines reports that may be downloaded in XLSX format, using axlsx.
##
class Admin::ReportsController < ApplicationController
  ##
  # GET /admin/reports
  ##
  def index
  end

  ##
  # A report containing a list of all users, and lists of users in each role.
  ##
  def roles
    ::Axlsx::Package.new do |p|
      wb = p.workbook
      datetime = wb.styles.add_style :format_code => 'dd/mm/yyyy hh:mm'

      #Add a worksheet with all users:
      wb.add_worksheet(name: "All Users") do |sheet|
        sheet.add_row(["Firstname", "Surname", "Email", "Last Login"])
        User.all.each do |user|
          sheet.add_row([user.first_name, user.last_name, user.email, user.last_sign_in_at], :style => [nil,nil,nil,datetime])
        end
      end

      #Add a worksheet for each role.
      Role.all().each do |role|
        wb.add_worksheet(:name => role.name.gsub(/\//, " - ")) do |sheet|
          sheet.add_row(["Firstname", "Surname", "Email", "Last Login"])
          role.users.each do |user|
            sheet.add_row([user.first_name, user.last_name, user.email, user.last_sign_in_at])
          end

          sheet.sheet_view.pane do |pane|
            pane.top_left_cell = "B2"
            pane.state = :frozen_split
            pane.y_split = 1
          end
        end
      end

      stream_workbook(p, "Roles.xlsx")
    end
  end

  ##
  # A report containing all the entries in the NewsletterSubscriber model.
  ##
  def newsletter_subscribers
    ::Axlsx::Package.new do |p|
      p.workbook.add_worksheet(:name => "Subscribers") do |sheet|
        NewsletterSubscriber.all().each do |subscriber|
          sheet.add_row([subscriber.email])
        end
      end

      stream_workbook(p, "Newsletter Subscribers.xlsx")
    end
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
    ::Axlsx::Package.new do |p|
      wb = p.workbook

      start_year = params[:first_year] || 1.years.ago.year
      end_year = params[:end_year] || 1.years.since.year

      current_date = Date.new(start_year, 1, 1)

      while current_date.year <= end_year
        next_date = current_date.months_since(6)

        sheet_name = "#{current_date.month}-#{current_date.year} - #{next_date.month}-#{next_date.year}"
        wb.add_worksheet(name: sheet_name) do |sheet|
          sheet.add_row(["Firstname", "Surname", "Email", "Staffing", "Past Shows", "Upcoming Shows"])

          User.all.each do |user|
            past_show_count = Show.joins(:users).where(["user_id = ? AND end_date < ? AND end_date >= ? AND end_date < ?", user.id, Date.today, current_date, next_date]).count
            upcoming_show_count = Show.joins(:users).where(["user_id = ? AND end_date >= ? AND end_date >= ? AND end_date < ?", user.id, Date.today, current_date, next_date]).count

            staffing_count = Admin::Staffing.joins(:staffing_jobs).where(["user_id = ? AND date >= ? AND date < ?", user.id, current_date, next_date]).count

            sheet.add_row([user.first_name, user.last_name, user.email, staffing_count, past_show_count, upcoming_show_count])
          end

          owes_staffing = wb.styles.add_style(:fg_color => "FF0000", :b => true, :type => :dxf)
          will_owe_staffing = wb.styles.add_style(:fg_color => "FF9900", :b => true, :type => :dxf)
          sheet.add_conditional_formatting("D:D", { :type => :cellIs, :operator => :lessThan, :formula => 'INDIRECT("RC[1]",0)', :dxfId => owes_staffing, :priority => 1 })
          sheet.add_conditional_formatting("D:D", { :type => :cellIs, :operator => :lessThan, :formula => 'INDIRECT("RC[1]",0) + INDIRECT("RC[2]",0)', :dxfId => will_owe_staffing, :priority => 2 })
        end

        current_date = next_date
      end

      stream_workbook(p, "Staffing.xlsx")
    end
  end

  private

  ##
  # Streams the workbook back to the client.
  ##
  def stream_workbook(package, filename)
    package.validate.each do |error|
      Rails.logger.warn "Error creating report with filename #{filename}: "
      Rails.logger.warn error
    end

    send_data package.to_stream.read, :filename => filename, :type=> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end
end
