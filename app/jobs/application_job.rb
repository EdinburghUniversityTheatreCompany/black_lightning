require "net/smtp"

class ApplicationJob < ActiveJob::Base
  # Declared first: Rescuable picks the LAST matching handler, so a catch-all declared after
  # the specific ones below would shadow them all.
  retry_on StandardError, wait: ->(executions) { executions * 2 }, attempts: 5

  retry_on ActiveRecord::Deadlocked

  # The record is gone, so there is nothing left to do.
  discard_on ActiveJob::DeserializationError

  # Mailersend answers a rate limit with 450 (SMTPServerBusy), and some 5xx are transient too.
  # 10 polynomial attempts span about 30 minutes, long enough for the window to reset.
  retry_on Net::SMTPFatalError, Net::SMTPServerBusy, wait: :polynomially_longer, attempts: 10
end
