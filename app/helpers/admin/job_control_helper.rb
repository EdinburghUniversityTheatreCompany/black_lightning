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
    Delayed::Job
  rescue
    false
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
    delayed_job.where(delayed_job_sql(type))
  end

  ##
  # Converts the given category into a where statement.
  ##
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

  ##
  # Checks the DJ Daemon is running
  ##
  def delayed_job_running?
    pid = File.read("#{Rails.root}/tmp/pids/delayed_job.pid").strip
    Process.kill(0, pid.to_i)
    true
  rescue Errno::ENOENT, Errno::ESRCH   # file or process not found
    false
  end
end
