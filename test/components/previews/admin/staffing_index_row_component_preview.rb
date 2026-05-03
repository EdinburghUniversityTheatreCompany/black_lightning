class Admin::StaffingIndexRowComponentPreview < Admin::ApplicationComponentPreview
  # Upcoming staffings grouped by show slug
  def default
    staffings_hash = Admin::Staffing.future
                                    .includes(:staffing_jobs, staffing_jobs: :user)
                                    .order(start_time: :asc)
                                    .group_by(&:slug)
    render Admin::StaffingIndexRowComponent.new(staffings_hash: staffings_hash)
  end

  # Archived staffings (shows warning colour when less than 70% filled)
  def archived
    staffings_hash = Admin::Staffing.past
                                    .includes(:staffing_jobs, staffing_jobs: :user)
                                    .order(start_time: :desc)
                                    .limit(30)
                                    .group_by(&:slug)
    render Admin::StaffingIndexRowComponent.new(staffings_hash: staffings_hash, archived: true)
  end
end
