class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Default queue is 'default'
  queue_as :default

  # Configure max attempts similar to delayed_job with exponential backoff
  retry_on StandardError, wait: ->(executions) { executions * 2 }, attempts: 5
end
