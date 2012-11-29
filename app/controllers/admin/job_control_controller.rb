class Admin::JobControlController < AdminController

  check_authorization

  def overview
    authorize! :read, :jobs
  end

  def working
    authorize! :read, :jobs
  end

  def pending
    authorize! :read, :jobs
  end

  def failed
    authorize! :read, :jobs
  end

  def remove
    authorize! :delete, :jobs
    Delayed::Job.find(params[:id]).delete
    redirect_to :back
  end

  def retry
    authorize! :manage, :jobs

    job = Delayed::Job.find(params[:id])
    job.attempts = 0
    job.run_at = Time.now
    job.failed_at = nil
    job.save

    redirect_to :back
  end

end
