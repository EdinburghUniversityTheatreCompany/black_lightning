Delayed::Worker.destroy_failed_jobs = false
Delayed::Worker.max_attempts = 5

class Delayed::Job < ApplicationRecord

  ##
  # Sets the number of attempts to 0, and failed_at to nil.
  ##
  def retry_job
    self.attempts = 0
    self.run_at = Time.now
    self.failed_at = nil
    self.save!
  end
end
