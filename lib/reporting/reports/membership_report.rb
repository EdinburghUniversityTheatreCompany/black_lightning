##
# A report containing all the entries in the NewsletterSubscriber model.
##
class Reports::MembershipReport

  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    p = Axlsx::Package.new

    p.workbook.add_worksheet(:name => "Members") do |sheet|
      sheet.add_row(["Firstname", "Surname", "Email"])
      User.with_role(:member).all.each do |user|
        sheet.add_row([user.first_name, user.last_name, user.email])
      end
    end

    return p
  end
end