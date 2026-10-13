# frozen_string_literal: true

##
# Retries a recurring-task enqueue that lost a MySQL deadlock. RecurringTask#enqueue rescues the
# EnqueueError and returns false, with no retry or failed-job row, so a lost occurrence is silent.
# Retrying is safe: RecurringExecution.record writes the job and execution rows in one
# transaction, and the unique index on (task_key, run_at) catches an attempt that did commit.
##
module RecurringEnqueueRetry
  MAX_ATTEMPTS = 3

  # Anything else (a validation failure, a dead connection) must keep surfacing.
  RETRYABLE = [ ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout ].freeze

  class << self
    # Re-raises once the attempts are spent, so Solid Queue's own error reporting still fires.
    def with_retries(task_key:, max_attempts: MAX_ATTEMPTS)
      attempts = 0

      begin
        attempts += 1
        yield
      rescue StandardError => e
        raise unless retryable?(e) && attempts < max_attempts

        sleep backoff(attempts)
        log_retry(task_key, attempts, e)
        retry
      end
    end

    # Solid Queue flattens the error into EnqueueError's message, but the cause keeps the real
    # class: match on the class, not the string.
    def retryable?(error)
      [ error, error.cause ].compact.any? { |e| RETRYABLE.any? { |klass| e.is_a?(klass) } }
    end

    private

    # Jitter matters more than the delay: it breaks the tie with whatever we collided with.
    def backoff(attempts)
      (0.05 * attempts) + Kernel.rand(0.05)
    end

    def log_retry(task_key, attempts, error)
      Rails.logger.warn(
        "[RecurringEnqueueRetry] #{task_key} lost a deadlock enqueuing (attempt #{attempts}), " \
        "retrying: #{error.message}"
      )
    end
  end
end
