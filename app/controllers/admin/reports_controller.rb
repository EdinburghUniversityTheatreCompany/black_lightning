class Admin::ReportsController < ApplicationController
  def index
  end

  def roles
    ::Axlsx::Package.new do |p|
      Role.all().each do |role|
        p.workbook.add_worksheet(:name => role.name.gsub(/\//, " - ")) do |sheet|
          sheet.add_row(["Firstname", "Surname", "Email"])
          role.users.each do |user|
            sheet.add_row([user.first_name, user.last_name, user.email])
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

  private
  def stream_workbook(package, filename)
    package.validate.each do |error|
      Rails.logger.warn "Error creating report with filename #{filename}: "
      Rails.logger.warn error
    end

    send_data package.to_stream.read, :filename => filename, :type=> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end
end
