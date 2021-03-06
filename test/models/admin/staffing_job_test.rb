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
  setup do
    @user = FactoryBot.create(:user)
    @staffing_debt = FactoryBot.create(:staffing_debt, user: @user)
    @staffing = FactoryBot.create(:staffing_that_does_count_towards_debt)
    @staffing_job = FactoryBot.create(:unstaffed_staffing_job, staffable: @staffing)
  end

  test 'js_start_time' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 1, start_time: DateTime.new(2020, 5, 19, 18, 30, 5, '+03:00'))
    assert_equal 1589902205, staffing.staffing_jobs.first.js_start_time
  end

  test 'js_end_time' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 1, end_time: DateTime.new(2020, 5, 19, 18, 30, 5, '-02:00'))
    assert_equal 1589920205, staffing.staffing_jobs.first.js_end_time
  end

  test 'completed' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, staffed_job_count: 1, start_time: DateTime.now.advance(days: -1))

    assert staffing.staffing_jobs.first.completed?
    staffing.update_attribute(:end_time, DateTime.now.advance(days: 1))
    assert_not staffing.staffing_jobs.first.completed?
  end

  test 'count towards debt' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, unstaffed_job_count: 1)
    job = staffing.staffing_jobs.first
    assert job.counts_towards_debt?

    job.name = 'Committee Rep'

    assert_not job.counts_towards_debt?

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
  # Associatins
  ##
  test 'associates with the oldest existing staffing_debt after adding user' do
    assert_nil @staffing_debt.admin_staffing_job, 'The staffing_debt already has a staffing_job associated with it. Did you modify the staffing_debt factory?' 

    newer_staffing_debt = FactoryBot.create(:staffing_debt, user: @user, due_by: @staffing_debt.due_by.advance(hours: 1))

    @staffing_job.user = @user
    @staffing_job.save!

    @staffing_debt.reload
    newer_staffing_debt.reload

    assert_not_nil @staffing_job.staffing_debt, 'The staffing_job has no staffing_debt associated with it'
    assert_not_nil @staffing_debt.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it'
    assert_nil newer_staffing_debt.admin_staffing_job, 'The newer_staffing_debt has a staffing_job associated with it'

    assert_equal @staffing_debt.admin_staffing_job.id, @staffing_job.id, "The id of the staffing_debt associated with the staffing_job is #{@staffing_job.id} instead of the expected value #{@staffing_debt.admin_staffing_job.id}"
  end

  test 'does not break when adding staffing_job to someone without outstanding staffing_debt' do
    other_user = FactoryBot.create(:user)
    @staffing_job.user = other_user
    @staffing_job.save!

    assert_nil @staffing_job.staffing_debt, 'The staffing job has associated with a staffing debt, even though the user is not in debt'
  end

  test 'removes staffing_job from staffing_debt when removing the user from the staffing_job' do
    @staffing_debt.admin_staffing_job = @staffing_job
    @staffing_debt.save!

    @staffing_job.reload

    assert_not_nil @staffing_job.staffing_debt, 'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job'

    @staffing_job.user = nil
    @staffing_job.save!

    @staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, 'The staffing_debt is not removed from the staffing_job after removing the user'
    assert_nil @staffing_debt.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after removing the user'
  end

  test 'does not associate with staffing_debt that is already staffed' do
    # This staffing_debt will now be associated with a staffing_job.
    @staffing_job.user = @user
    @staffing_job.save!
    @staffing_debt.reload

    assert_equal @staffing_job.staffing_debt.id, @staffing_debt.id, 'The staffing_job is not associated with the staffing_debt'

    # Check that the other_staffing_job does not associate with the staffing_debt.
    other_staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, start_time: @staffing.start_time.advance(hours:1), end_time: @staffing.end_time.advance(hours:1))
    other_staffing_job = FactoryBot.create(:unstaffed_staffing_job, staffable: other_staffing, user: @user)

    @staffing_debt.reload
    @staffing_job.reload
    other_staffing_job.reload

    assert_equal @staffing_job.staffing_debt.id, @staffing_debt.id, 'The staffing_job is not associated with the staffing_debt'
    assert_nil other_staffing_job.staffing_debt, 'The other_staffing_job associated with the staffing_debt'
  end

  test 'does not associate staffing_job again when the user does not change' do
    @staffing_job.user = @user
    @staffing_job.save!

    @staffing_debt.reload

    @staffing_job.name = 'ThisIsDefinitelySomethingElse'
    assert_not @staffing_job.user_id_changed?, 'The user associated with the staffing job is marked as changed'
    @staffing_job.save!
    assert_not @staffing_job.user_id_changed?, 'The user associated with the staffing job is marked as changed'
  end

  test 'associates with different staffing_debt when changing the user' do
    @staffing_debt.admin_staffing_job = @staffing_job
    @staffing_debt.save!

    @staffing_job.reload

    assert_not_nil @staffing_job.staffing_debt, 'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job'

    new_user = FactoryBot.create(:user)
    new_staffing_debt = FactoryBot.create(:staffing_debt)
    new_staffing_debt.user = new_user
    new_staffing_debt.save!

    @staffing_job.user = new_user
    @staffing_job.save!

    @staffing_debt.reload
    new_staffing_debt.reload

    assert_nil @staffing_debt.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after changing the user'

    assert_not_nil @staffing_job.staffing_debt, 'The staffing job has no staffing debt associated with it after changing the user'
    assert_not_nil new_staffing_debt.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it after changing the user'

    assert_equal new_staffing_debt.admin_staffing_job.id, @staffing_job.id, "The id of the staffing_debt associated with the staffing_job is #{new_staffing_debt.admin_staffing_job.id} instead of the expected value #{@staffing_job.id}"
  end

  test 'is not associated with a staffing_job anymore after changing the user to someone not in debt' do
    @staffing_debt.admin_staffing_job = @staffing_job
    @staffing_debt.save!

    @staffing_job.reload

    assert_not_nil @staffing_job.staffing_debt, 'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job'

    @staffing_job.user = FactoryBot.create(:user)
    @staffing_job.save!

    @staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, 'The staffing_debt is not removed from the staffing_job after changing the user'
    assert_nil @staffing_debt.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after changing the user'
  end

  test 'does not associate when the staffing_job does not count towards_debt' do
    @staffing_job.staffable = FactoryBot.create(:staffing_that_does_not_count_towards_debt)
    helper_test_does_not_associate_even_though('the staffing associated with the staffing job does not count towards debt')
  end

  test 'does not associate when the name of the job is "Committee Rep"' do
    @staffing_job.name = 'Committee Rep'

    helper_test_does_not_associate_even_though('the staffing_debt has name "Committee Rep"')
  end

  test 'does not associate when the staffing debt is forgiven' do
    @staffing_debt.forgive

    helper_test_does_not_associate_even_though('the staffing_debt is forgiven')
  end

  private

  def helper_test_does_not_associate_even_though(reason)
    @staffing_job.user = @user
    @staffing_job.save!
    @staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, "The staffing job has staffing debt associated with it even though #{reason}"
    assert_nil @staffing_debt.admin_staffing_job, "The staffing_debt has a staffing_job associated with it even though #{reason}"
  end
end
