##
# A report containing all events and some basic info about them
##
class Reports::Events
  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    package = Axlsx::Package.new

    package.workbook.add_worksheet(name: 'Events') do |sheet|
      sheet.add_row(['Event Name', 'Type', 'Start Date', 'End Date'])
      Event.all.each do |_user|
        sheet.add_row([event.name, event.type, event.start_date, event.type])
      end
    end

    return package
  end
end
