require "test_helper"

# Two recurring tasks due at the same second deadlock in InnoDB, and RecurringTask#enqueue
# swallows the error and returns false -- so a lost occurrence looks like one never scheduled.
class RecurringEnqueueRetryTest < ActiveSupport::TestCase
  def deadlock_error
    raise ActiveRecord::Deadlocked, "Mysql2::Error: Deadlock found when trying to get lock"
  rescue ActiveRecord::Deadlocked => inner
    # Solid Queue re-raises database errors as EnqueueError; raising inside the rescue is what
    # makes the original the Ruby `cause`, exactly as the gem does it.
    begin
      raise SolidQueue::Job::EnqueueError, "ActiveRecord::Deadlocked: #{inner.message}"
    rescue SolidQueue::Job::EnqueueError => wrapped
      wrapped
    end
  end

  test "a deadlocked enqueue is retried until it succeeds" do
    attempts = 0

    result = RecurringEnqueueRetry.with_retries(task_key: "probe") do
      attempts += 1
      raise deadlock_error if attempts < 3

      :enqueued
    end

    assert_equal :enqueued, result
    assert_equal 3, attempts
  end

  test "it gives up rather than retrying forever, so a real failure still surfaces" do
    attempts = 0

    assert_raises(SolidQueue::Job::EnqueueError) do
      RecurringEnqueueRetry.with_retries(task_key: "probe", max_attempts: 3) do
        attempts += 1
        raise deadlock_error
      end
    end

    assert_equal 3, attempts, "should stop at max_attempts"
  end

  # A validation failure or a dead connection is a real problem; retrying hides it.
  test "an error that is not a deadlock is raised immediately" do
    attempts = 0

    assert_raises(SolidQueue::Job::EnqueueError) do
      RecurringEnqueueRetry.with_retries(task_key: "probe") do
        attempts += 1
        raise SolidQueue::Job::EnqueueError, "ActiveRecord::RecordInvalid: something is wrong"
      end
    end

    assert_equal 1, attempts, "a non-deadlock must not be retried"
  end

  test "a lock wait timeout is retried too" do
    attempts = 0

    RecurringEnqueueRetry.with_retries(task_key: "probe") do
      attempts += 1
      raise ActiveRecord::LockWaitTimeout, "Lock wait timeout exceeded" if attempts < 2

      :enqueued
    end

    assert_equal 2, attempts
  end

  # The class is checked rather than the message, because Solid Queue flattens the original into
  # a string; Ruby's implicit cause chaining is what keeps the real class reachable.
  test "it identifies a deadlock through the EnqueueError wrapper by class, not message" do
    assert RecurringEnqueueRetry.retryable?(deadlock_error)
    assert_instance_of ActiveRecord::Deadlocked, deadlock_error.cause
  end

  test "it does not treat an unrelated error as retryable" do
    error = StandardError.new("Deadlock found when trying to get lock")

    assert_not RecurringEnqueueRetry.retryable?(error),
               "a message that merely mentions a deadlock is not one"
  end

  test "the retry is wired into SolidQueue's recurring enqueue" do
    task = SolidQueue::RecurringTask.new(key: "probe", class_name: "ActiveJob::Base", schedule: "every hour")

    assert_not_equal SolidQueue::RecurringTask, task.method(:enqueue_and_record).owner,
                     "enqueue_and_record should be overridden by the prepended retry module"
  end
end
