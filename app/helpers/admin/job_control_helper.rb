##
# Nicked from delayed_job_web
# https://github.com/ejschmitt/delayed_job_web/blob/master/lib/delayed_job_web/application/app.rb
#
# A quick way of accessing which delayed_jobs are in which category.
##
module Admin::JobControlHelper
  ##
  # Fetches the Delayed::Job model
  ##
  def delayed_job
    begin
      return Delayed::Job
    rescue
      # Can't really test that.
      # :nocov:
      return false
      # :nocov:
    end
  end

  ##
  # Gets delayed_jobs in the specified category.
  #
  # Acceptable categories are:
  # * Enqueued
  # * Working
  # * Failed
  # * Pending
  ##
  def delayed_jobs(type)
    return delayed_job.where(delayed_job_sql(type))
  end

  ##
  # Converts the given category into a where statement.
  ##
  def delayed_job_sql(type)
    case type
    when :enqueued
      return ''
    when :working
      return 'locked_at is not null'
    when :failed
      return 'last_error is not null'
    when :pending
      return 'attempts = 0'
    end
  end

  ##
  # Checks the DJ Daemon is running
  ##
  def delayed_job_running?
    pid = File.read("#{Rails.root}/tmp/pids/delayed_job.pid").strip
    # :nocov:
    Process.kill(0, pid.to_i)
    return true
    # :nocov:
  # file or process not found.
  rescue Errno::ENOENT, Errno::ESRCH
    return false
  end
end
