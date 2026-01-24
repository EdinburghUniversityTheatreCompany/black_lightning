require "net/smtp"

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Default queue is 'default'
  queue_as :default

  # SMTP errors - retry with polynomial backoff
  # Net::SMTPFatalError: 5xx permanent errors (some are transient)
  # Net::SMTPServerBusy: 4xx temporary errors including Mailersend 450 rate limits
  # :polynomially_longer uses (executions ** 4) + jitter
  # 10 attempts spans ~30 minutes, giving rate limit windows time to reset
  retry_on Net::SMTPFatalError, Net::SMTPServerBusy, wait: :polynomially_longer, attempts: 10

  # Configure max attempts similar to delayed_job with exponential backoff
  retry_on StandardError, wait: ->(executions) { executions * 2 }, attempts: 5
end
