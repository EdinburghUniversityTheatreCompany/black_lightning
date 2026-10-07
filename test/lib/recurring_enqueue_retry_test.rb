require "test_helper"

# Two recurring tasks due at the same second deadlock in InnoDB, and RecurringTask#enqueue
# swallows the error and returns false -- so a lost occurrence looks like one never scheduled.
class RecurringEnqueueRetryTest < ActiveSupport::TestCase
  def deadlock_error
    raise ActiveRecord::Deadlocked, "Mysql2::Error: Deadlock found when trying to get lock"
  rescue ActiveRecord::Deadlocked => inner
    # Solid Queue re-raises database errors as EnqueueError; raising inside the rescue makes
    # the original the Ruby `cause`, as the gem does.
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

  # A validation failure or a dead connection is a real problem; retrying hides it. A message
  # that merely mentions a deadlock is not one: the class is matched through the cause.
  test "an error that is not a deadlock is raised immediately" do
    attempts = 0

    assert_raises(SolidQueue::Job::EnqueueError) do
      RecurringEnqueueRetry.with_retries(task_key: "probe") do
        attempts += 1
        raise SolidQueue::Job::EnqueueError, "Deadlock found when trying to get lock"
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

  test "the retry is wired into SolidQueue's recurring enqueue" do
    task = SolidQueue::RecurringTask.new(key: "probe", class_name: "ActiveJob::Base", schedule: "every hour")

    assert_not_equal SolidQueue::RecurringTask, task.method(:enqueue_and_record).owner,
                     "enqueue_and_record should be overridden by the prepended retry module"
  end
end
