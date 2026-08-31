# frozen_string_literal: true

##
# Retries a recurring-task enqueue that lost a MySQL deadlock. `RecurringTask#enqueue` rescues
# the EnqueueError, logs it and returns false -- no retry and no failed-job row -- so without
# this a lost occurrence is indistinguishable from one that was never scheduled.
#
# Retrying is safe rather than merely convenient: `RecurringExecution.record` wraps the job row
# and the execution row in ONE transaction, so a deadlock rolls back both and there is never a
# half-enqueued occurrence to duplicate. A first attempt that did commit is caught by the unique
# index on (task_key, run_at).
##
module RecurringEnqueueRetry
  MAX_ATTEMPTS = 3

  # Anything else -- a validation failure, a dead connection -- is a real problem that must keep
  # surfacing rather than be retried away.
  RETRYABLE = [ ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout ].freeze

  class << self
    ##
    # Re-raises once the attempts are spent, so Solid Queue's own error reporting still fires.
    ##
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

    ##
    # Solid Queue flattens the database error into an EnqueueError's message, but Ruby's implicit
    # cause chaining keeps the real class reachable -- so match on that, not on the string.
    ##
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
