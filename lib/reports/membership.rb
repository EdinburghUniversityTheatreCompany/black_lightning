##
# A report containing all the entries in the NewsletterSubscriber model.
##
class Reports::Membership
  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    package = Axlsx::Package.new

    package.workbook.add_worksheet(name: 'Members') do |sheet|
      sheet.add_row(%w(Firstname Surname Email))
      User.with_role(:member).all.each do |user|
        sheet.add_row([user.first_name, user.last_name, user.email])
      end
    end

    return package
  end
end
