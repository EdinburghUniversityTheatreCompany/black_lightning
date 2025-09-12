##
# A report containing all the entries in the NewsletterSubscriber model.
##
class Reports::NewsletterSubscribers
  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    package = Axlsx::Package.new

    package.workbook.add_worksheet(name: "Subscribers") do |sheet|
      NewsletterSubscriber.all.each do |subscriber|
        sheet.add_row([ subscriber.email ])
      end
    end

    package
  end
end
