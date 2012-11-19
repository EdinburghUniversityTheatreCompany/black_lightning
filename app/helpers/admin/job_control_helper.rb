module Admin::JobControlHelper
  def delayed_job
    begin
      Delayed::Job
    rescue
      false
    end
  end

  def delayed_jobs(type)
    delayed_job.where(delayed_job_sql(type))
  end

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
