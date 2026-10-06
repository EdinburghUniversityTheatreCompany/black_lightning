class Admin::StaffingIndexRowComponentPreview < Admin::ApplicationComponentPreview
  def default
    staffings_hash = Admin::Staffing.future
                                    .includes(:staffing_jobs, staffing_jobs: :user)
                                    .order(start_time: :asc)
                                    .group_by(&:slug)
    render Admin::StaffingIndexRowComponent.new(staffings_hash: staffings_hash)
  end

  # A show under 70% filled gets the warning colour.
  def archived
    staffings_hash = Admin::Staffing.past
                                    .includes(:staffing_jobs, staffing_jobs: :user)
                                    .order(start_time: :desc)
                                    .limit(30)
                                    .group_by(&:slug)
    render Admin::StaffingIndexRowComponent.new(staffings_hash: staffings_hash, archived: true)
  end
end
