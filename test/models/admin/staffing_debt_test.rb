require 'test_helper'

class Admin::StaffingDebtTest < ActiveSupport::TestCase
  setup do 
    @user = FactoryGirl.create(:user)
  end

  test "associates with existing staffing_job that counts towards staffing" do 
    staffing = FactoryGirl.create(:staffing_that_does_count_towards_debt)
    staffing_job = FactoryGirl.create(:unstaffed_staffing_job, staffable: staffing)
    staffing_job.user_id = @user.id
    staffing_job.save

    assert_nil staffing_job.staffing_debt, 'The staffing_job has a staffing_debt associated with it before one was created'

    staffing_debt = FactoryGirl.create(:staffing_debt, user: @user)

    staffing_job.reload
    staffing_debt.reload

    assert_not_nil staffing_debt.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it'
    assert_not_nil staffing_job.staffing_debt, 'The staffing_job has no staffing_debt associated with it'

    assert_equal staffing_debt.admin_staffing_job.id, staffing_job.id,
    "The id of the staffing_job associated with the staffing_debt is #{staffing_debt.admin_staffing_job.id} instead of the expected value #{staffing_job.id}"
  end

  test "does not break when adding staffing_debt to someone without unassociated staffing_jobs" do
    staffing = FactoryGirl.create(:staffing_that_does_count_towards_debt)
    staffing_job = FactoryGirl.create(:unstaffed_staffing_job, user: @user, staffable: staffing)

    other_user = FactoryGirl.create(:user)
    staffing_debt = FactoryGirl.create(:staffing_debt, user: other_user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt has associated with a staffing_job, even though this user has none'
  end

  test "does not associate with existing staffing_job by another user" do
    staffing = FactoryGirl.create(:staffing_that_does_count_towards_debt)
    other_user = FactoryGirl.create(:user)
    staffing_job = FactoryGirl.create(:staffed_staffing_job, staffable: staffing, user: other_user)
    
    staffing_debt = FactoryGirl.create(:staffing_debt, user: @user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt is associated with a staffing_job'
    assert_nil staffing_job.staffing_debt, 'The staffing_job is associated with a staffing_job'
  end

  test "does not associate with existing staffing_job that already has a staffing_debt associated" do
    staffing = FactoryGirl.create(:staffing_that_does_count_towards_debt)
    staffing_job = FactoryGirl.create(:unstaffed_staffing_job, user: @user, staffable: staffing)
    existing_staffing_debt = FactoryGirl.create(:staffing_debt, admin_staffing_job: staffing_job, user: @user)
    staffing_job.reload

    assert_equal existing_staffing_debt.admin_staffing_job.id, staffing_job.id, 'The existing_staffing_debt is not associated with the staffing_job'

    new_staffing_debt = FactoryGirl.create(:staffing_debt, user: @user)

    assert_equal existing_staffing_debt.id, staffing_job.staffing_debt.id, 'The staffing_job is not associated with the existing_staffing_job anymore'
    assert_nil new_staffing_debt.admin_staffing_job, 'The new_staffing_debt is associated with a staffing_job'
  end

  test "does not associate with existing staffing_job that does not count toward staffing" do
    staffing = FactoryGirl.create(:staffing_that_does_not_count_towards_debt)
    staffing_job = FactoryGirl.create(:staffed_staffing_job, staffable: staffing, user: @user)
    
    staffing_debt = FactoryGirl.create(:staffing_debt, user: @user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt is associated with a staffing_job'
    assert_nil staffing_job.staffing_debt, 'The staffing_job is associated with a staffing_job'
  end

  test "does not associate with existing staffing_job that is a committee rep slot" do
    staffing = FactoryGirl.create(:staffing_that_does_count_towards_debt)
    staffing_job = FactoryGirl.create(:staffed_staffing_job, staffable: staffing, user: @user, name: 'Committee Rep')
    
    staffing_debt = FactoryGirl.create(:staffing_debt, user: @user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt is associated with a staffing_job'
    assert_nil staffing_job.staffing_debt, 'The staffing_job is associated with a staffing_job'
  end
end
