# frozen_string_literal: true

# See RecurringEnqueueRetry for why a retry is safe, and config/recurring.yml for the staggering
# this is the net under.
Rails.application.config.to_prepare do
  SolidQueue::RecurringTask.prepend(Module.new do
    private

    def enqueue_and_record(run_at:)
      RecurringEnqueueRetry.with_retries(task_key: key) { super }
    end
  end)
end
