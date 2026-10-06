require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  class RaisingJob < ApplicationJob
    cattr_accessor :error
    cattr_accessor :performed, default: 0

    def perform
      self.class.performed += 1
      raise error
    end
  end

  test "an SMTP rate limit gets 10 attempts, any other error 5" do
    assert_equal 10, attempts_for(Net::SMTPServerBusy.new("450", message: "rate limited"))
    assert_equal 5, attempts_for(RuntimeError.new)
  end

  test "a job whose record is gone is discarded after one attempt" do
    error = begin
      raise "the record is gone"
    rescue
      ActiveJob::DeserializationError.new
    end

    assert_equal 1, attempts_for(error)
  end

  private

  # Retries run inline, and the last failure is re-raised once they are used up.
  def attempts_for(error)
    RaisingJob.error = error
    RaisingJob.performed = 0
    queue_adapter.perform_enqueued_jobs = queue_adapter.perform_enqueued_at_jobs = true
    begin
      RaisingJob.perform_later
    rescue StandardError
      nil
    end
    RaisingJob.performed
  ensure
    queue_adapter.perform_enqueued_jobs = queue_adapter.perform_enqueued_at_jobs = false
  end
end
