require 'test_helper'

class Admin::StaffingJobTest < ActiveSupport::TestCase
  setup do 
    @staffing_job = FactoryGirl.create(:unstaffed_staffing_job)
    @user = FactoryGirl.create(:user)
  end

  test "associates_with_staffing_debt_after_adding_user" do
    staffing_debt = FactoryGirl.create(:staffing_debt)
    staffing_debt.user = @user
    staffing_debt.save

    assert_nil staffing_debt.admin_staffing_job 'The staffing_debt already has a staffing_job associated with it. Did you modify the staffing_debt factory?' 

    @staffing_job.user = @user
    @staffing_job.save

    staffing_debt.reload

    assert_not_nil @staffing_job.staffing_debt, 'The staffing job has no staffing debt associated with it.'
    assert_not_nil staffing_debt.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it'
    
    assert_equal staffing_debt.admin_staffing_job.id, @staffing_job.id, 
    "The id of the staffing_debt associated with the staffing_job is #{staffing_debt.admin_staffing_job.id} instead of the expected value #{@staffing_job.id}."
  end

  test "does_not_break_when_adding_staffing_job_to_someone_without_outstanding_debt" do
    @staffing_job.user = @user
    @staffing_job.save
  end

  test "removes_staffing_job_from_staffing_debt_when_removing_the_user_from_the_staffing_job" do
    staffing_debt = FactoryGirl.create(:staffing_debt)
    staffing_debt.user = @user
    staffing_debt.admin_staffing_job = @staffing_job
    staffing_debt.save

    @staffing_job.reload

    assert_not_nil @staffing_job.staffing_debt,'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job.'

    @staffing_job.user = nil
    @staffing_job.save

    staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, 'The staffing_debt is not removed from the staffing_job after removing the user.'
    assert_nil staffing_debt.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after removing the user.'
  end

  test "does_not_associate_staffing_job_again_when_the_user_does_not_change" do
    staffing_debt = FactoryGirl.create(:staffing_debt)
    staffing_debt.user = @user
    staffing_debt.save

    @staffing_job.user = @user
    @staffing_job.save

    staffing_debt.reload

    @staffing_job.name = "ThisIsDefinitelySomethingElse"
    assert_not @staffing_job.user_id_changed?, 'The user associated with the staffing job is marked as changed.'
    @staffing_job.save
    assert_not @staffing_job.user_id_changed?, 'The user associated with the staffing job is marked as changed.'
  end

  test "associates_with_different_staffing_job_when_changing_the_user" do 
    staffing_debt = FactoryGirl.create(:staffing_debt)
    staffing_debt.user = @user
    staffing_debt.admin_staffing_job = @staffing_job
    staffing_debt.save

    @staffing_job.reload

    assert_not_nil @staffing_job.staffing_debt,'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job.'

    new_user = FactoryGirl.create(:user)
    new_staffing_debt = FactoryGirl.create(:staffing_debt)
    new_staffing_debt.user = new_user
    new_staffing_debt.save

    @staffing_job.user = new_user
    @staffing_job.save

    staffing_debt.reload
    new_staffing_debt.reload

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after changing the user.'
    
    assert_not_nil @staffing_job.staffing_debt, 'The staffing job has no staffing debt associated with it after changing the user.'
    assert_not_nil new_staffing_debt.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it after changing the user.'
    
    assert_equal new_staffing_debt.admin_staffing_job.id, @staffing_job.id, 
    "The id of the staffing_debt associated with the staffing_job is #{new_staffing_debt.admin_staffing_job.id} instead of the expected value #{@staffing_job.id}."
  end

  test "associates_with_no_staffing_job_when_changing_the_user_to_someone_not_in_debt" do
    staffing_debt = FactoryGirl.create(:staffing_debt)
    staffing_debt.user = @user
    staffing_debt.admin_staffing_job = @staffing_job
    staffing_debt.save

    @staffing_job.reload

    assert_not_nil @staffing_job.staffing_debt,'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job.'

    @staffing_job.user = FactoryGirl.create(:user)
    @staffing_job.save

    staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, 'The staffing_debt is not removed from the staffing_job after changing the user.'
    assert_nil staffing_debt.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after changing the user.'
  end
end
