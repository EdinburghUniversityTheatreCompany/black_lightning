class Admin::ReportsController < ApplicationController
  def index
  end

  def roles
    ::Axlsx::Package.new do |p|
      Role.all().each do |role|
        p.workbook.add_worksheet(:name => role.name) do |sheet|
          sheet.add_row(["Firstname", "Surname", "Email"])
          role.users.each do |user|
            sheet.add_row([user.first_name, user.last_name, user.email])
          end

          sheet.sheet_view.pane do |pane|
            pane.top_left_cell = "B2"
            pane.state = :frozen_split
            pane.y_split = 1
          end
        end
      end

      file = ::Tempfile.new('roles.xlsx')

      begin
        p.serialize(file.path)

        send_file file.path, :filename => 'roles.xlsx'
      ensure
        file.close
        file.unlink
      end
    end
  end
end
