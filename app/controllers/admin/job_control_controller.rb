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
    @title = 'Delayed Jobs'
    authorize! :read, Delayed::Backend::ActiveRecord::Job
  end

  ##
  # GET /admin/jobs/working
  ##
  def working
    @title = 'Working Delayed Jobs'
    @description = 'The list below contains jobs currently being processed.'

    @type = :working

    authorize! :read, Delayed::Backend::ActiveRecord::Job

    render action: :list
  end

  ##
  # GET /admin/jobs/pending
  ##
  def pending
    @title = 'Pending Delayed Jobs'
    @description = 'The list below contains jobs waiting to be processed.'

    @type = :pending

    authorize! :read, Delayed::Backend::ActiveRecord::Job

    render action: :list
  end

  ##
  # GET /admin/jobs/failed
  ##
  def failed
    @title = 'Failed Delayed Jobs'
    @description = 'The list below contains jobs that have an error message.'

    @type = :failed

    authorize! :read, Delayed::Backend::ActiveRecord::Job

    render action: :list
  end

  ##
  # GET /admin/jobs/remove/1
  ##
  def remove
    authorize! :delete, Delayed::Backend::ActiveRecord::Job
    Delayed::Job.find(params[:id]).delete
    redirect_back(fallback_location: admin_jobs_overview_path)
  end

  ##
  # GET /admin/jobs/retry/1
  ##
  def retry
    authorize! :manage, Delayed::Backend::ActiveRecord::Job

    job = Delayed::Job.find(params[:id])

    job.retry_job

    redirect_back(fallback_location: admin_jobs_overview_path)
  end
end
