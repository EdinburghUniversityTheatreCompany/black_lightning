##
# A report showing the number of shows a user has been in, and the number of staffing slots
# they have completed.
#
# Broken into 6 month periods.
#
# Accepts two parameters:
# * @start_year The first year to include in the report (default = 1 year ago)
# * @end_year   The last year to include in the report (default = 1 year ahead)
##
class StaffingReport
  def initialize(start_year, end_year)
    @start_year = start_year
    @end_year   = end_year
  end

  ##
  # Returns the Axlsx package for the report.
  ##
  def create
    package = Axlsx::Package.new

    wb = package.workbook

    current_date = Date.new(@start_year, 1, 1)

    while current_date.year <= @end_year
      next_date = current_date.months_since(6)

      sheet_name = "#{current_date.month}-#{current_date.year} - #{next_date.month}-#{next_date.year}"
      wb.add_worksheet(name: sheet_name) do |sheet|
        sheet.add_row(['Firstname', 'Surname', 'Email', 'Staffing', 'Past Shows', 'Upcoming Shows'])

        User.with_role(:member).each do |user|
          past_show_count = user.shows.where(['end_date < ? AND end_date >= ? AND end_date < ?', Date.today, current_date, next_date]).count
          upcoming_show_count = user.shows.where(['end_date >= ? AND end_date >= ? AND end_date < ?', Date.today, current_date, next_date]).count

          staffing_count = user.staffings.joins(:staffing_jobs).where(['start_time >= ? AND start_time < ?', current_date, next_date]).distinct.count

          sheet.add_row([user.first_name, user.last_name, user.email, staffing_count, past_show_count, upcoming_show_count])
        end

        owes_staffing = wb.styles.add_style(fg_color: 'FF0000', b: true, type: :dxf)
        will_owe_staffing = wb.styles.add_style(fg_color: 'FF9900', b: true, type: :dxf)
        sheet.add_conditional_formatting('D:D', type: :cellIs, operator: :lessThan, formula: 'INDIRECT("RC[1]",0)', dxfId: owes_staffing, priority: 1)
        sheet.add_conditional_formatting('D:D', type: :cellIs, operator: :lessThan, formula: 'INDIRECT("RC[1]",0) + INDIRECT("RC[2]",0)', dxfId: will_owe_staffing, priority: 2)
      end

      current_date = next_date
    end

    return package
  end
end
