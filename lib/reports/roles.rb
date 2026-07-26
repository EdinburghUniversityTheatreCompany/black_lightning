##
# A report containing a list of all users, and lists of users in each role.
##
class Reports::Roles
  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    package = Axlsx::Package.new
    wb = package.workbook
    datetime = wb.styles.add_style format_code: "dd/mm/yyyy hh:mm"

    # Add a worksheet with all users. pluck the four emitted columns so the
    # whole users table isn't instantiated as AR objects while the sheet grows.
    wb.add_worksheet(name: "All Users") do |sheet|
      sheet.add_row([ "Firstname", "Surname", "Email", "Last Login" ])
      User.order(:last_name, :first_name).pluck(:first_name, :last_name, :email, :last_sign_in_at).each do |first_name, last_name, email, last_login|
        sheet.add_row([ first_name, last_name, email, last_login ], style: [ nil, nil, nil, datetime ])
      end
    end

    # Add a worksheet for each role. Plucking per role (rather than
    # includes(:users)) means only one role's members are resident at a time,
    # instead of every user of every role held simultaneously.
    Role.order(:name).each do |role|
      wb.add_worksheet(name: role.name.gsub(/\//, " - ")) do |sheet|
        sheet.add_row([ "Firstname", "Surname", "Email", "Last Login" ])
        role.users.order(:last_name, :first_name).pluck(:first_name, :last_name, :email, :last_sign_in_at).each do |first_name, last_name, email, last_login|
          sheet.add_row([ first_name, last_name, email, last_login ])
        end

        sheet.sheet_view.pane do |pane|
          pane.top_left_cell = "B2"
          pane.state = :frozen_split
          pane.y_split = 1
        end
      end
    end

    package
  end
end
