require 'test_helper'

# TODO: These tests can be severely improved.
class Admin::JobControlHelperTest < ActionView::TestCase
  test 'get delayed job' do
    assert_equal Delayed::Job, delayed_job
  end

  test 'get delayed jobs of type' do
    assert_equal [], delayed_jobs(:enqueued)
    assert_equal [], delayed_jobs(:working)
    assert_equal [], delayed_jobs(:failed)
    assert_equal [], delayed_jobs(:pending)
  end

  test 'delayed job running' do
    assert_equal false, delayed_job_running?
  end
end
