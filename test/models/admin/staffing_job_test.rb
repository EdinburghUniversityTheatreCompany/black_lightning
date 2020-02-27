require 'test_helper'

class Admin::StaffingJobTest < ActiveSupport::TestCase
  setup do 
    staffing = FactoryGirl.create(:staffing_that_counts_towards_debt)
    staffing.save

    @staffing_job = FactoryGirl.create(:unstaffed_staffing_job, staffable: staffing)

    @user = FactoryGirl.create(:user)
  end

  test "associates with staffing_debt after adding user" do
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

  test "does not break when adding staffing_job to someone without outstanding staffing_debt" do
    @staffing_job.user = @user
    @staffing_job.save

    assert_nil @staffing_job.staffing_debt, 'The staffing job has associated with a staffing debt, even though the user is not in debt.'
  end

  test "removes staffing_job from staffing_debt when removing the user from the staffing_job" do
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

  test "does not associate staffing_job again when the user does not change" do
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

  test "associates with different staffing_job when changing the user" do 
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

  test "is not associated with a staffing_job anymore after changing the user to someone not in debt" do
    staffing_debt = FactoryGirl.create(:staffing_debt, user: @user, admin_staffing_job: @staffing_job)
    staffing_debt.save

    @staffing_job.reload

    assert_not_nil @staffing_job.staffing_debt,'The staffing_job has no staffing_debt associated after associating the staffing_debt with the same staffing_job.'

    @staffing_job.user = FactoryGirl.create(:user)
    @staffing_job.save

    staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, 'The staffing_debt is not removed from the staffing_job after changing the user.'
    assert_nil staffing_debt.admin_staffing_job, 'The staffing_job is not removed from the staffing_debt after changing the user.'
  end

  test "does not associate when the staffing_job does not count towards_debt" do
    staffing_debt = FactoryGirl.create(:staffing_debt)
    staffing_debt.user = @user
    staffing_debt.save

    assert_nil staffing_debt.admin_staffing_job 'The staffing_debt has a staffing_job associated with it. Did you modify the staffing_debt factory?' 
    
    @staffing_job.staffable = FactoryGirl.create(:staffing_that_does_not_count_towards_debt)
    @staffing_job.user = @user
    @staffing_job.save

    staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, 'The staffing job has staffing debt associated with it even though the staffable/staffing associated with the job does not count towards staffing.'
    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt has a staffing_job associated with it even though the staffable/staffing associated with the job does not count towards staffing.'
  end

  test "does not associate when the name of the job is Committee Rep" do
    staffing_debt = FactoryGirl.create(:staffing_debt)
    staffing_debt.user = @user
    staffing_debt.save

    assert_nil staffing_debt.admin_staffing_job 'The staffing_debt has a staffing_job associated with it. Did you modify the staffing_debt factory?' 
    
    @staffing_job.user = @user
    @staffing_job.name = "Committee Rep"
    @staffing_job.save

    staffing_debt.reload

    assert_nil @staffing_job.staffing_debt, 'The staffing job has staffing debt associated with it even though the name of the job is "Committee Rep".'
    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt has a staffing_job associated with it even though the name of the job is "Committee Rep".'
  end
end
