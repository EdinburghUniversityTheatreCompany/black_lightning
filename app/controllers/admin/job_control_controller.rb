##
# Controller for delayed jobs.
#
# See the delayed_job gem documentation for more details.
##
class Admin::JobControlController < AdminController

  check_authorization

  ##
  # GET /admin/jobs/overview
  ##
  def overview
    @title = "Delayed Jobs"
    authorize! :read, Delayed::Backend::ActiveRecord::Job
  end

  ##
  # GET /admin/jobs/working
  ##
  def working
    @title = "Working Delayed Jobs"
    authorize! :read, Delayed::Backend::ActiveRecord::Job
  end

  ##
  # GET /admin/jobs/pending
  ##
  def pending
    @title = "Pending Delayed Jobs"
    authorize! :read, Delayed::Backend::ActiveRecord::Job
  end

  ##
  # GET /admin/jobs/failed
  ##
  def failed
    @title = "Failed Delayed Jobs"
    authorize! :read, Delayed::Backend::ActiveRecord::Job
  end

  ##
  # GET /admin/jobs/remove/1
  ##
  def remove
    authorize! :delete, Delayed::Backend::ActiveRecord::Job
    Delayed::Job.find(params[:id]).delete
    redirect_to :back
  end

  ##
  # GET /admin/jobs/retry/1
  #
  # Sets the number of attempts to 0, and failed_at to nil.
  ##
  def retry
    authorize! :manage, Delayed::Backend::ActiveRecord::Job

    job = Delayed::Job.find(params[:id])
    job.attempts = 0
    job.run_at = Time.now
    job.failed_at = nil
    job.save!

    redirect_to :back
  end

end
