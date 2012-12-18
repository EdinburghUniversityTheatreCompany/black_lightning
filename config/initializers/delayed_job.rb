Delayed::Worker.destroy_failed_jobs = false
Delayed::Worker.max_attempts = 5

class Delayed::Job < ActiveRecord::Base
  attr_accessible :description
end