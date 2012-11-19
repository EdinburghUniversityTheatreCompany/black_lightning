class Admin::JobControlController < AdminController

  def overview
  end

  def working
  end

  def pending
  end

  def failed
  end

  def remove
    delayed_job.find(params[:id]).delete
    redirect_to :back
  end

  def retry
    job = delayed_job.find(params[:id])
    job.update_attributes(:run_at => Time.now, :failed_at => nil)
    redirect_to :back
  end

end
