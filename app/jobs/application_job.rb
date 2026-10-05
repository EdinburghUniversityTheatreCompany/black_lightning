require "net/smtp"

class ApplicationJob < ActiveJob::Base
  retry_on ActiveRecord::Deadlocked

  # The record is gone, so there is nothing left to do.
  discard_on ActiveJob::DeserializationError

  queue_as :default

  # Mailersend answers a rate limit with 450 (SMTPServerBusy), and some 5xx are transient too.
  # 10 polynomial attempts span about 30 minutes, long enough for the window to reset.
  retry_on Net::SMTPFatalError, Net::SMTPServerBusy, wait: :polynomially_longer, attempts: 10

  # Configure max attempts similar to delayed_job with exponential backoff
  retry_on StandardError, wait: ->(executions) { executions * 2 }, attempts: 5
end
