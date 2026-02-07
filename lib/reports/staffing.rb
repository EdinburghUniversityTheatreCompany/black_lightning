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
class Reports::Staffing
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

    # Preload all members once
    members = User.with_role(:member).order(:last_name, :first_name).to_a
    member_ids = members.map(&:id)

    while current_date.year <= @end_year
      next_date = current_date.months_since(6)

      sheet_name = "#{current_date.month}-#{current_date.year} - #{next_date.month}-#{next_date.year}"
      wb.add_worksheet(name: sheet_name) do |sheet|
        sheet.add_row([ "Firstname", "Surname", "Email", "Staffing", "Past Shows", "Upcoming Shows" ])

        # BATCH: Query all show counts for all members in this period
        # Manual join needed for polymorphic association
        past_shows = TeamMember
          .joins("INNER JOIN events ON events.id = team_members.teamwork_id AND team_members.teamwork_type = 'Show'")
          .where(user_id: member_ids)
          .where("events.end_date < ? AND events.end_date >= ? AND events.end_date < ?",
                 Date.current, current_date, next_date)
          .reorder(nil)
          .group(:user_id)
          .count

        upcoming_shows = TeamMember
          .joins("INNER JOIN events ON events.id = team_members.teamwork_id AND team_members.teamwork_type = 'Show'")
          .where(user_id: member_ids)
          .where("events.end_date >= ? AND events.end_date >= ? AND events.end_date < ?",
                 Date.current, current_date, next_date)
          .reorder(nil)
          .group(:user_id)
          .count

        # BATCH: Query all staffing counts for all members in this period
        # Manual join needed for polymorphic staffable association
        staffing_counts = Admin::StaffingJob
          .joins("INNER JOIN admin_staffings ON admin_staffings.id = admin_staffing_jobs.staffable_id AND admin_staffing_jobs.staffable_type = 'Admin::Staffing'")
          .where(user_id: member_ids)
          .where("admin_staffings.start_time >= ? AND admin_staffings.start_time < ?", current_date, next_date)
          .group(:user_id)
          .select("user_id, COUNT(DISTINCT admin_staffings.id) as count")
          .each_with_object({}) { |result, hash| hash[result.user_id] = result.count }

        members.each do |user|
          sheet.add_row([
            user.first_name,
            user.last_name,
            user.email,
            staffing_counts[user.id] || 0,
            past_shows[user.id] || 0,
            upcoming_shows[user.id] || 0
          ])
        end

        owes_staffing = wb.styles.add_style(fg_color: "FF0000", b: true, type: :dxf)
        will_owe_staffing = wb.styles.add_style(fg_color: "FF9900", b: true, type: :dxf)
        sheet.add_conditional_formatting("D:D", type: :cellIs, operator: :lessThan, formula: 'INDIRECT("RC[1]",0)', dxfId: owes_staffing, priority: 1)
        sheet.add_conditional_formatting("D:D", type: :cellIs, operator: :lessThan, formula: 'INDIRECT("RC[1]",0) + INDIRECT("RC[2]",0)', dxfId: will_owe_staffing, priority: 2)
      end

      current_date = next_date
    end

    package
  end
end
