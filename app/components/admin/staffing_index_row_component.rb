class Admin::StaffingIndexRowComponent < ViewComponent::Base
  def initialize(staffings_hash:, archived: nil)
    @staffings_hash = staffings_hash
    @archived = archived
  end

  private

  def rows
    @staffings_hash.map do |url, staffings|
      jobs = staffings.flat_map(&:staffing_jobs)
      filled = jobs.count(&:user_id)

      {
        href: helpers.grid_admin_staffings_path(url, archived: @archived),
        show_title: staffings.first.show_title,
        date_range: helpers.time_range_string(*staffings.map { |s| s.start_time.to_date }.minmax, true, :short),
        positions_filled: "#{filled} of #{jobs.size} filled",
        show_warning: jobs.any? && filled.fdiv(jobs.size) <= 0.7
      }
    end
  end
end
