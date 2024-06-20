require 'test_helper'

class Admin::JobControlControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    # Turn on delayed jobs to test they can be removed and reset.
    Delayed::Worker.delay_jobs = true
  end

  teardown do
    # Turn off delayed jobs back off
    Delayed::Worker.delay_jobs = false
  end

  test 'should get overview' do
    get :overview
    assert_response :success
  end

  test 'should get working' do
    get :working
    assert_response :success
  end

  test 'should get pending' do
    get :pending
    assert_response :success
  end

  test 'should get failed' do
    get :failed
    assert_response :success
  end

  test 'should delete job' do
    job = Delayed::Job.new
    job.save!

    request.env['HTTP_REFERER'] = admin_jobs_overview_path

    assert_difference('Delayed::Job.count', -1) do
      get :remove, params: {id: job.id}    end

    assert_redirected_to admin_jobs_overview_path
  end

  test 'should reset job' do
    job = Delayed::Job.new
    job.attempts = 3
    job.run_at = Time.current
    job.failed_at = Time.current
    job.save!

    request.env['HTTP_REFERER'] = admin_jobs_overview_path

    get :retry, params: {id: job.id}
    assert_redirected_to admin_jobs_overview_path

    job.reload

    assert_equal job.attempts, 0
    assert_nil   job.failed_at
  end
end
