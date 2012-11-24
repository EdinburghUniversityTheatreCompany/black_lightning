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
    delayed_job.find(params[:id]).delete
    redirect_to :back
  end

  def retry
    authorize! :manage, :jobs
    job = delayed_job.find(params[:id])
    job.update_attributes(:run_at => Time.now, :failed_at => nil)
    redirect_to :back
  end

end
