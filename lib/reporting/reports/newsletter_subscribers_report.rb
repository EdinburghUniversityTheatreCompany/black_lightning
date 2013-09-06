##
# A report containing all the entries in the NewsletterSubscriber model.
##
class Reports::NewsletterSubscribersReport

  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    p = Axlsx::Package.new

    p.workbook.add_worksheet(:name => "Subscribers") do |sheet|
      NewsletterSubscriber.all().each do |subscriber|
        sheet.add_row([subscriber.email])
      end
    end

    return p
  end
end