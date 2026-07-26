##
# A report containing all the entries in the NewsletterSubscriber model.
##
class Reports::NewsletterSubscribers
  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    require "caxlsx" # lazy: kept out of the boot heap (Gemfile require:false)
    package = Axlsx::Package.new

    package.workbook.add_worksheet(name: "Subscribers") do |sheet|
      # pluck the one column we emit rather than instantiating a model per row.
      NewsletterSubscriber.pluck(:email).each do |email|
        sheet.add_row([ email ])
      end
    end

    package
  end
end
