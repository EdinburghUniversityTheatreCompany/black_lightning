require 'test_helper'
require 'rake'

# Tests the debt rake tasks.
class DebtTaskTest < ActiveSupport::TestCase
  test 'Should notify new debtors' do
    new_debts = FactoryBot.create_list(:overdue_maintenance_debt, 2, due_by: Date.current.advance(days: -1))
    new_debts += FactoryBot.create_list(:overdue_staffing_debt, 3, due_by: Date.current.advance(days: -1))

    # Older debts. Create notifications so they are not included in the unrepentant debts.
    older_debts = FactoryBot.create_list(:overdue_maintenance_debt, 4, due_by: Date.current.advance(days: -2))
    older_debts.each do |older_debt|
      FactoryBot.create(:reminder_debt_notification, user: older_debt.user, sent_on: Date.current.advance(days: -3))
    end

    assert_difference 'Admin::DebtNotification.where(notification_type: :initial_notification).count', new_debts.count do
      assert_difference 'ActionMailer::Base.deliveries.count', new_debts.count do
        Tasks::Logic::Debt.notify_debtors
      end
    end

    mail_sample = ActionMailer::Base.deliveries.last
    assert 'Notification of Debt', mail_sample.subject
  end

  test 'Should notify unrepentant debtors' do
    unrepentant_debts = FactoryBot.create_list(:overdue_maintenance_debt, 2, due_by: Date.current.advance(days: -15))
    unrepentant_debts += FactoryBot.create_list(:overdue_staffing_debt, 3, due_by: Date.current.advance(days: -15))

    unrepentant_debts.each do |unrepentant_debt|
      FactoryBot.create(:initial_debt_notification, user: unrepentant_debt.user, sent_on: Date.current.advance(days: -15))
    end

    # Add some debts with debtors that have already been notified in the past days.
    already_notified_debts = [FactoryBot.create(:overdue_maintenance_debt, due_by: Date.current.advance(days: -2)), FactoryBot.create(:overdue_maintenance_debt, due_by: Date.current.advance(days: -12))]
    already_notified_debts.each do |already_notified_debt|
      FactoryBot.create(:initial_debt_notification, user: already_notified_debt.user, sent_on: Date.current.advance(days: -3))
    end

    assert_difference 'Admin::DebtNotification.where(notification_type: :reminder).count', unrepentant_debts.count do
      assert_difference 'ActionMailer::Base.deliveries.count', unrepentant_debts.count do
        Tasks::Logic::Debt.notify_debtors
      end
    end

    mail_sample = ActionMailer::Base.deliveries.last
    assert 'Reminder of Debt', mail_sample.subject
  end

  test 'Should clear all maintenance debts, staffing debts and debt notifications' do
    FactoryBot.create_list(:maintenance_debt, 5)
    FactoryBot.create_list(:staffing_debt, 5)
    FactoryBot.create_list(:initial_debt_notification, 5)
    FactoryBot.create_list(:staffing, 5, staffed_job_count: 2)

    Tasks::Logic::Debt.clear_all_debts

    assert Admin::MaintenanceDebt.all.empty?
    assert Admin::StaffingDebt.all.empty?
    assert Admin::DebtNotification.all.empty?
    assert Admin::Staffing.all.empty?
    assert Admin::StaffingJob.all.empty?
  end
end
