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

    # Add a worksheet with all users:
    wb.add_worksheet(name: "All Users") do |sheet|
      sheet.add_row([ "Firstname", "Surname", "Email", "Last Login" ])
      User.order(:last_name, :first_name).each do |user|
        sheet.add_row([ user.first_name, user.last_name, user.email, user.last_sign_in_at ], style: [ nil, nil, nil, datetime ])
      end
    end

    # Add a worksheet for each role - preload users to prevent N+1 queries
    Role.includes(:users).order(:name).each do |role|
      wb.add_worksheet(name: role.name.gsub(/\//, " - ")) do |sheet|
        sheet.add_row([ "Firstname", "Surname", "Email", "Last Login" ])
        # Use preloaded users (no additional queries)
        role.users.sort_by { |u| [ u.last_name, u.first_name ] }.each do |user|
          sheet.add_row([ user.first_name, user.last_name, user.email, user.last_sign_in_at ])
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
