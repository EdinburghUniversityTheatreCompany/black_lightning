class Admin::StaffingIndexRowComponent < ViewComponent::Base
  def initialize(staffings_hash:, archived: nil)
    @staffings_hash = staffings_hash
    @archived = archived
  end

  private

  def rows
    @staffings_hash.map do |url, staffings|
      filled = 0
      unfilled = 0
      staffings.each do |staffing|
        staffing.staffing_jobs.each { |job| job.user_id.nil? ? unfilled += 1 : filled += 1 }
      end
      total = filled + unfilled

      dates = staffings.map { |s| s.start_time.to_date }.sort
      date_range = helpers.time_range_string(dates.first, dates.last, true, :short)

      {
        url: url,
        show_title: staffings.first.show_title,
        date_range: date_range,
        positions_filled: "#{filled} of #{total} filled",
        show_warning: total > 0 && (filled.to_f / total.to_f) <= 0.7
      }
    end
  end
end
