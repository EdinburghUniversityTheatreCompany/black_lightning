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

  def delayed_job
    begin
      Delayed::Job
    rescue
      false
    end
  end
  helper_method :delayed_job

  def delayed_jobs(type)
    delayed_job.where(delayed_job_sql(type))
  end
  helper_method :delayed_jobs

  def delayed_job_sql(type)
    case type
    when :enqueued
      ''
    when :working
      'locked_at is not null'
    when :failed
      'last_error is not null'
    when :pending
      'attempts = 0'
    end
  end

end
