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

    # pluck, so the whole users table is never instantiated as AR objects.
    wb.add_worksheet(name: "All Users") do |sheet|
      sheet.add_row([ "Firstname", "Surname", "Email", "Last Login" ])
      User.order(:last_name, :first_name).pluck(:first_name, :last_name, :email, :last_sign_in_at).each do |first_name, last_name, email, last_login|
        sheet.add_row([ first_name, last_name, email, last_login ], style: [ nil, nil, nil, datetime ])
      end
    end

    # Plucking per role keeps one role's users resident at a time.
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
