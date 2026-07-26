##
# A report containing all the entries in the NewsletterSubscriber model.
##
class Reports::Membership
  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    package = Axlsx::Package.new

    package.workbook.add_worksheet(name: "Members") do |sheet|
      sheet.add_row(%w[Firstname Surname Email])
      # pluck the three emitted columns; no need to build a User object per row.
      User.with_role(:member).pluck(:first_name, :last_name, :email).each do |first_name, last_name, email|
        sheet.add_row([ first_name, last_name, email ])
      end
    end

    package
  end
end
