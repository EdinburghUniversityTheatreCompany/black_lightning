# == Schema Information
#
# Table name: admin_staffing_debts
#
# *id*::                    <tt>integer, not null, primary key</tt>
# *user_id*::               <tt>integer</tt>
# *show_id*::               <tt>integer</tt>
# *due_by*::                <tt>date</tt>
# *admin_staffing_job_id*:: <tt>integer</tt>
# *created_at*::            <tt>datetime, not null</tt>
# *updated_at*::            <tt>datetime, not null</tt>
# *converted*::             <tt>boolean</tt>
# *forgiven*::              <tt>boolean, default(FALSE)</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class Admin::StaffingDebtTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:user)
  end

  test 'fulfilled' do
    staffing_debt = FactoryBot.create(:staffing_debt)

    assert_not staffing_debt.fulfilled

    staffing_debt.forgiven = true

    assert staffing_debt.fulfilled

    staffing_debt.forgiven = false
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, end_time: DateTime.now.advance(days: -1))
    staffing_job = FactoryBot.create(:staffing_job, user: staffing_debt.user, staffable: staffing)

    staffing_debt.admin_staffing_job = staffing_job

    assert staffing_debt.reload.fulfilled
  end

  test 'unfulfilled on self' do
    staffing = FactoryBot.create(:staffing, end_time: DateTime.now.advance(days: -1), unstaffed_job_count: 1)
    fulfilled_debt = FactoryBot.create(:staffing_debt)

    staffing.staffing_jobs.first.staffing_debt = fulfilled_debt
    fulfilled_debt.reload

    forgiven_debt = FactoryBot.create(:staffing_debt, forgiven: true)

    unfulfilled_debt = FactoryBot.create(:staffing_debt)

    assert_includes Admin::StaffingDebt.unfulfilled, unfulfilled_debt, 'The list of unfulfilled debt does not include the unfulfilled debt'
    assert_not_includes Admin::StaffingDebt.unfulfilled, fulfilled_debt, 'The list of unfulfilled debt includes the fulfilled debt'
    assert_not_includes Admin::StaffingDebt.unfulfilled, forgiven_debt, 'The list of unfulfilled dbet includes the forgiven debt'

    assert Admin::StaffingDebt.unfulfilled.none?(&:fulfilled)
  end

  test 'forgive' do
    staffing_debt = FactoryBot.create(:staffing_debt, forgiven: false)
    staffing_job = FactoryBot.create(:staffing_job, staffing_debt: staffing_debt, user: staffing_debt.user)

    assert staffing_job.id, staffing_debt.reload.admin_staffing_job&.id

    staffing_debt.forgive

    assert staffing_debt.forgiven
    assert_nil staffing_debt.reload.admin_staffing_job
  end

  test 'status and css class' do
    staffing_debt = FactoryBot.create :staffing_debt

    # Not signed up before deadline
    staffing_debt.due_by = Date.today.advance(days: 1)
    assert_equal :not_signed_up, staffing_debt.status
    assert_equal 'warning', staffing_debt.css_class

    # Not signed up after debt deadline -> causing debt
    staffing_debt.due_by = Date.today.advance(days: -1)
    assert_equal :causing_debt, staffing_debt.status
    assert_equal 'error', staffing_debt.css_class

    # Forgiven
    staffing_debt.forgive
    assert_equal :forgiven, staffing_debt.status
    assert_equal 'success', staffing_debt.css_class

    user = FactoryBot.create(:user)
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt, end_time: DateTime.now.advance(days: 3))
    staffed_job = FactoryBot.create(:unstaffed_staffing_job, user: user, staffable: staffing)
    other_staffing_debt = FactoryBot.create(:staffing_debt, user: user, due_by: Date.today.advance(days: 1), admin_staffing_job: staffed_job)

    # Awaiting staffing before debt deadline
    assert_equal :awaiting_staffing, other_staffing_debt.status
    assert_equal '', other_staffing_debt.css_class

    # Awaiting staffing after debt deadline
    other_staffing_debt.update_attribute(:due_by, Date.today.advance(days: -1))
    assert_equal :awaiting_staffing, other_staffing_debt.status
    assert_equal '', other_staffing_debt.css_class

    # After staffing deadline -> completed staffing
    staffing.update_attribute(:end_time, DateTime.now.advance(days: -1))
    assert_equal :completed_staffing, other_staffing_debt.status
    assert_equal 'success', other_staffing_debt.css_class
  end

  ##
  # Associations
  ##
  test 'associates with existing staffing_job that counts towards staffing' do
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: @user)

    assert_nil staffing_job.staffing_debt, 'The staffing_job has a staffing_debt associated with it before one was created'

    staffing_debt = FactoryBot.create(:staffing_debt, user: @user)

    staffing_job.reload
    staffing_debt.reload

    assert_not_nil staffing_debt.admin_staffing_job, 'The staffing_debt has no staffing_job associated with it'
    assert_not_nil staffing_job.staffing_debt, 'The staffing_job has no staffing_debt associated with it'

    assert_equal staffing_debt.admin_staffing_job.id, staffing_job.id,
                 "The id of the staffing_job associated with the staffing_debt is #{staffing_debt.admin_staffing_job.id} instead of the expected value #{staffing_job.id}"
  end

  test 'does not break when adding staffing_debt to someone without unassociated staffing_jobs' do
    _staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: @user)

    other_user = FactoryBot.create(:user)
    staffing_debt = FactoryBot.create(:staffing_debt, user: other_user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt has associated with a staffing_job, even though this user has none'
  end

  test 'does not associate with existing staffing_job by another user' do
    other_user = FactoryBot.create(:user)
    staffing_job = FactoryBot.create(:staffed_staffing_job, user: other_user)

    staffing_debt = FactoryBot.create(:staffing_debt, user: @user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt is associated with a staffing_job'
    assert_nil staffing_job.staffing_debt, 'The staffing_job is associated with a staffing_job'
  end

  test 'does not associate with existing staffing_job that already has a staffing_debt associated' do
    staffing_job = FactoryBot.create(:unstaffed_staffing_job, user: @user)
    existing_staffing_debt = FactoryBot.create(:staffing_debt, admin_staffing_job: staffing_job, user: @user)
    staffing_job.reload

    assert_equal existing_staffing_debt.admin_staffing_job.id, staffing_job.id, 'The existing_staffing_debt is not associated with the staffing_job'

    new_staffing_debt = FactoryBot.create(:staffing_debt, user: @user)

    assert_equal existing_staffing_debt.id, staffing_job.staffing_debt.id, 'The staffing_job is not associated with the existing_staffing_job anymore'
    assert_nil new_staffing_debt.admin_staffing_job, 'The new_staffing_debt is associated with a staffing_job'
  end

  test 'does not associate with existing staffing_job that does not count toward staffing' do
    staffing = FactoryBot.create(:staffing_that_does_not_count_towards_debt)
    staffing_job = FactoryBot.create(:staffed_staffing_job, staffable: staffing, user: @user)

    staffing_debt = FactoryBot.create(:staffing_debt, user: @user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt is associated with a staffing_job'
    assert_nil staffing_job.staffing_debt, 'The staffing_job is associated with a staffing_job'
  end

  test 'does not associate with existing staffing_job that is a committee rep slot' do
    staffing = FactoryBot.create(:staffing_that_does_count_towards_debt)
    staffing_job = FactoryBot.create(:staffed_staffing_job, staffable: staffing, user: @user, name: 'Committee Rep')

    staffing_debt = FactoryBot.create(:staffing_debt, user: @user)

    assert_nil staffing_debt.admin_staffing_job, 'The staffing_debt is associated with a staffing_job'
    assert_nil staffing_job.staffing_debt, 'The staffing_job is associated with a staffing_job'
  end
end
