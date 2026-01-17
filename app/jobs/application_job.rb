require "net/smtp"

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Default queue is 'default'
  queue_as :default

  # SMTP rate limiting errors need longer backoff than standard errors
  # :polynomially_longer uses (executions ** 4) + jitter
  # Waits roughly: 1s, 16s, 81s, 256s, 625s across 5 attempts
  retry_on Net::SMTPFatalError, wait: :polynomially_longer, attempts: 5

  # Configure max attempts similar to delayed_job with exponential backoff
  retry_on StandardError, wait: ->(executions) { executions * 2 }, attempts: 5
end
