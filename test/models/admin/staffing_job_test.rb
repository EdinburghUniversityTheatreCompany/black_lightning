# == Schema Information
#
# Table name: admin_staffing_jobs
#
# *id*::             <tt>integer, not null, primary key</tt>
# *name*::           <tt>string(255)</tt>
# *staffable_id*::   <tt>integer</tt>
# *user_id*::        <tt>integer</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
# *staffable_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class Admin::StaffingJobTest < ActiveSupport::TestCase
  test 'js_start_time' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 1, start_time: DateTime.new(2020, 5, 19, 18, 30, 5, '+03:00'))
    assert_equal 1589902205, staffing.staffing_jobs.first.js_start_time
  end

  test 'js_end_time' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 1, end_time: DateTime.new(2020, 5, 19, 18, 30, 5, '-02:00'))
    assert_equal 1589920205, staffing.staffing_jobs.first.js_end_time
  end

  test 'completed' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, staffed_job_count: 1, start_time: DateTime.current.advance(days: -1))

    assert staffing.staffing_jobs.first.completed?
    staffing.update_attribute(:end_time, DateTime.current.advance(days: 1))
    assert_not staffing.staffing_jobs.first.completed?
  end

  test 'count towards debt' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 1)
    job = staffing.staffing_jobs.first
    assert job.counts_towards_debt?
  end

  test 'committee rep does not count towards debt' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 1)
    job = staffing.staffing_jobs.first
    job.name = 'Committee Rep'

    assert_not job.counts_towards_debt?
  end

  test 'does not count towards debt when the staffing does not count towards debt' do
    non_counting_staffing = FactoryBot.create(:staffing_that_does_not_count_towards_debt, unstaffed_job_count: 1)

    assert_not non_counting_staffing.staffing_jobs.first.counts_towards_debt?
  end

  test 'unassociated staffing jobs that count towards debt' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 3)
    unassociated_job_that_counts_towards_debt = staffing.staffing_jobs.first

    associated_job_that_counts_towards_debt = staffing.staffing_jobs[1]
    associated_job_that_counts_towards_debt.staffing_debt = FactoryBot.create(:staffing_debt)

    committee_rep_job = staffing.staffing_jobs[2]
    committee_rep_job.update_attribute(:name, 'Committee Rep')

    non_counting_staffing = FactoryBot.create(:staffing_that_does_not_count_towards_debt, unstaffed_job_count: 1)
    job_that_does_not_count_towards_debt = non_counting_staffing.staffing_jobs.first

    test_jobs = Admin::StaffingJob.unassociated_staffing_jobs_that_count_towards_debt

    assert_includes test_jobs, unassociated_job_that_counts_towards_debt, 'The staffing jobs do not contain the unasociated job that counts'
    assert_not_includes test_jobs, associated_job_that_counts_towards_debt, 'The staffing jobs contain the asociated job that counts'
    assert_not_includes test_jobs, committee_rep_job, 'The staffing jobs contain the committee rep job'
    assert_not_includes test_jobs, job_that_does_not_count_towards_debt, 'The staffing jobs contain the job that does not count towards debt'
  end

  ##
  # Associations
  ##
  test 'associates with the oldest existing staffing_debt after adding user' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)
    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt already has a staffing_job associated with it. Did you modify the staffing_debt factory?' 

    # Create a staffing job that is due LATER than the existing one.
    later_staffing_debt = FactoryBot.create(:staffing_debt, user: user, due_by: staffing_debt.due_by.advance(hours: 1))

    # Create a staffing job that can associate with a staffing debt.
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: user)

    # This job should have associated with the earliest debt (staffing_debt)
    assert_not_nil staffing_job.reload.staffing_debt, 'The staffing_job has no staffing_debt associated with it'
    assert_not_nil staffing_debt.reload.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it'
    assert_nil later_staffing_debt.reload.admin_staffing_job, 'The newer_staffing_debt has a staffing_job associated with it'

    assert_equal staffing_debt.admin_staffing_job.id, staffing_job.id, "The id of the staffing_debt associated with the staffing_job is #{staffing_job.id} instead of the expected value #{staffing_debt.admin_staffing_job.id}"
  end

  test 'does not break when adding staffing_job to someone without outstanding staffing_debt' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: user)

    # Check that the staffing job associates with the staffing debt.
    assert_equal staffing_job, staffing_debt.reload.admin_staffing_job, 'The staffing_job is not associated with the staffing_debt'

    # Change the user on the job to a new user.
    other_user = FactoryBot.create(:user)

    staffing_job.update(user: other_user)

    # Check that the job and debt have dissassociated.
    assert_nil staffing_job.reload.staffing_debt, 'The staffing job has associated with a staffing debt, even though the user is not in debt'
    assert_nil staffing_debt.reload.admin_staffing_job, 'The staffing_debt has a staffing_job associated with it, even though the user on the job has just changed.'
  end

  test 'removes staffing_job from staffing_debt when removing the user from the staffing_job' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: user)

    assert_not_nil staffing_job.reload.staffing_debt, 'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job'

    # Remove the user from the staffing job.
    staffing_job.update(user: nil)

    # Assert that the job and debt are no longer linked even after removing the user from the job.
    assert_nil staffing_job.reload.staffing_debt, 'The staffing_debt is not removed from the staffing_job after removing the user'
    assert_nil staffing_debt.reload.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after removing the user'
  end

  test 'does not associate with staffing_debt that is already staffed' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: user)

    assert_equal staffing_job.reload.staffing_debt, staffing_debt, 'The staffing_job is not associated with the staffing_debt'

    # Create a staffing job that happens later. This means it should not override the linking.
    later_staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, start_time: staffing_job.staffable.start_time.advance(hours: 1), end_time: staffing_job.staffable.end_time.advance(hours:1))
    later_staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: user)

    assert_equal staffing_job.reload.staffing_debt, staffing_debt, 'The staffing_job is not associated with the staffing_debt'
    assert_nil later_staffing_job.reload.staffing_debt, 'The later_staffing_job associated with the staffing_debt'
  end

  test 'associates with different staffing_debt when changing the user' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: user)

    assert_equal staffing_job.reload.staffing_debt, staffing_debt, 'The staffing_job is not associated with the staffing_debt'

    # Create a new user with a debt
    new_staffing_debt = FactoryBot.create(:staffing_debt)

    # Change the staffing_job user to the new user, so the job should associate with new_staffing_debt
    staffing_job.update(user: new_staffing_debt.user)

    assert_nil staffing_debt.reload.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after changing the user'

    assert_not_nil staffing_job.reload.staffing_debt, 'The staffing job has no staffing debt associated with it after changing the user'
    assert_not_nil new_staffing_debt.reload.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it after changing the user'

    assert_equal new_staffing_debt.admin_staffing_job, staffing_job, "The id of the staffing_debt associated with the staffing_job is #{new_staffing_debt.admin_staffing_job.id} instead of the expected value #{staffing_job.id}"
  end

  test 'does not associate when the staffing_job does not count towards_debt because the value on the staffable changes' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: staffing_debt.user)

    # Assert they associated.
    assert_equal staffing_job, staffing_debt.reload.admin_staffing_job

    # They should be disassociated after changing it to does not count towards debt.
    staffing_job.staffable.update(counts_towards_debt: false)

    helper_test_does_not_associate_even_though(staffing_debt, staffing_job, 'the staffing associated with the staffing job does not count towards debt')
  end

  test 'does not associate when the staffing_job does not count towards_debt because the staffable changes' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: staffing_debt.user)

    # Assert they associated.
    assert_equal staffing_job, staffing_debt.reload.admin_staffing_job

    # They should be disassociated after changing it to does not count towards debt.
    staffing_job.update(staffable: FactoryBot.create(:staffing_that_does_not_count_towards_debt))

    helper_test_does_not_associate_even_though(staffing_debt, staffing_job, 'the staffing associated with the staffing job does not count towards debt')
  end

  test 'does not associate when the name of the job is "Committee Rep"' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)

    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: staffing_debt.user, name: 'Committee Rep')

    helper_test_does_not_associate_even_though(staffing_debt, staffing_job, 'the staffing_debt has name "Committee Rep"')
  end

  test 'does not associate when the staffing debt is forgiven' do
    user = users(:member)
    staffing_debt = FactoryBot.create(:staffing_debt, user: user)

    staffing_debt.forgive

    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: staffing_debt.user)

    helper_test_does_not_associate_even_though(staffing_debt, staffing_job, 'the staffing_debt is forgiven')
  end

  private

  def helper_test_does_not_associate_even_though(staffing_debt, staffing_job, reason)
    assert_nil staffing_job.reload.staffing_debt, "The staffing job has staffing debt associated with it even though #{reason}"
    assert_nil staffing_debt.reload.admin_staffing_job, "The staffing_debt has a staffing_job associated with it even though #{reason}"
  end
end
