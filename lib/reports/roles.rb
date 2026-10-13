##
# A report containing a list of all users, and lists of users in each role.
##
class Reports::Roles
  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    require "caxlsx" # lazy: kept out of the boot heap (Gemfile require:false)
    package = Axlsx::Package.new
    wb = package.workbook
    datetime = wb.styles.add_style format_code: "dd/mm/yyyy hh:mm"

    wb.add_worksheet(name: "All Users") { |sheet| add_users(sheet, User, datetime) }

    Role.order(:name).each do |role|
      wb.add_worksheet(name: role.name.gsub(/\//, " - ")) do |sheet|
        add_users(sheet, role.users, datetime)

        sheet.sheet_view.pane do |pane|
          pane.top_left_cell = "B2"
          pane.state = :frozen_split
          pane.y_split = 1
        end
      end
    end

    package
  end

  private

  # pluck, so the whole users table is never instantiated as AR objects, and a role's users are
  # resident one role at a time.
  def add_users(sheet, users, datetime)
    sheet.add_row([ "Firstname", "Surname", "Email", "Last Login" ])
    users.order(:last_name, :first_name).pluck(:first_name, :last_name, :email, :last_sign_in_at).each do |row|
      sheet.add_row(row, style: [ nil, nil, nil, datetime ])
    end
  end
end
