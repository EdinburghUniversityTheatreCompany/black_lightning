require "test_helper"
require "rake"

# Tests the debt rake tasks.
class DebtTaskTest < ActiveSupport::TestCase
  test "Should notify new debtors" do
    new_debts = FactoryBot.create_list(:overdue_maintenance_debt, 2, due_by: Date.current.advance(days: -1))
    new_debts += FactoryBot.create_list(:overdue_staffing_debt, 3, due_by: Date.current.advance(days: -1))

    # Older debts. Create notifications so they are not included in the unrepentant debts.
    older_debts = FactoryBot.create_list(:overdue_maintenance_debt, 4, due_by: Date.current.advance(days: -2))
    older_debts.each do |older_debt|
      FactoryBot.create(:reminder_debt_notification, user: older_debt.user, sent_on: Date.current.advance(days: -3))
    end

    assert_difference "Admin::DebtNotification.where(notification_type: :initial_notification).count", new_debts.count do
      assert_difference "ActionMailer::Base.deliveries.count", new_debts.count do
        Tasks::Logic::Debt.notify_debtors
      end
    end

    mail_sample = ActionMailer::Base.deliveries.last
    assert_equal "Notification of Debt", mail_sample.subject
  end

  test "Should notify unrepentant debtors" do
    unrepentant_debts = FactoryBot.create_list(:overdue_maintenance_debt, 2, due_by: Date.current.advance(days: -15))
    unrepentant_debts += FactoryBot.create_list(:overdue_staffing_debt, 3, due_by: Date.current.advance(days: -15))

    unrepentant_debts.each do |unrepentant_debt|
      FactoryBot.create(:initial_debt_notification, user: unrepentant_debt.user, sent_on: Date.current.advance(days: -15))
    end

    # Add some debts with debtors that have already been notified in the past days.
    already_notified_debts = [ FactoryBot.create(:overdue_maintenance_debt, due_by: Date.current.advance(days: -2)), FactoryBot.create(:overdue_maintenance_debt, due_by: Date.current.advance(days: -12)) ]
    already_notified_debts.each do |already_notified_debt|
      FactoryBot.create(:initial_debt_notification, user: already_notified_debt.user, sent_on: Date.current.advance(days: -3))
    end

    assert_difference "Admin::DebtNotification.where(notification_type: :reminder).count", unrepentant_debts.count do
      assert_difference "ActionMailer::Base.deliveries.count", unrepentant_debts.count do
        Tasks::Logic::Debt.notify_debtors
      end
    end

    mail_sample = ActionMailer::Base.deliveries.last
    assert "Reminder of Debt", mail_sample.subject
  end

  test "Should clear all maintenance debts, staffing debts and debt notifications" do
    FactoryBot.create_list(:maintenance_debt, 2)
    FactoryBot.create_list(:staffing_debt, 2)
    FactoryBot.create_list(:initial_debt_notification, 2)
    FactoryBot.create_list(:staffing, 2, staffed_job_count: 2)

    Tasks::Logic::Debt.clear_all_debts

    assert Admin::MaintenanceDebt.all.empty?
    assert Admin::StaffingDebt.all.empty?
    assert Admin::DebtNotification.all.empty?
    assert Admin::Staffing.all.empty?
    assert Admin::StaffingJob.all.empty?
  end

  test "expire outdated debt should remove staffing debts older than a year but preserve younger debts" do
    staffing_debt_older_than_a_year = FactoryBot.create(:staffing_debt, due_by: Date.current - 365.days)
    staffing_debt_younger_than_a_year = FactoryBot.create(:staffing_debt, due_by: Date.current - 364.days)

    # Ensure the debt is in the future so awaiting staffing
    staffing_debt_awaiting_staffing = FactoryBot.create(:staffing_debt, due_by: Date.current - 2.year, with_staffing_job: true)
    staffing_debt_awaiting_staffing.admin_staffing_job.staffable.update(start_time: Date.current + 3.days, end_time: Date.current + 4.days)
    assert_equal :awaiting_staffing, staffing_debt_awaiting_staffing.status

    staffing_debt_already_staffed = FactoryBot.create(:staffing_debt, due_by: Date.current - 3.year, with_staffing_job: true)
    staffing_debt_already_staffed.admin_staffing_job.staffable.update(start_time: Date.current - 4.days, end_time: Date.current - 3.days)
    assert_equal :completed_staffing, staffing_debt_already_staffed.status

    Tasks::Logic::Debt.expire_outdated_debt

    assert_equal :expired, staffing_debt_older_than_a_year.reload.status
    assert_equal :causing_debt, staffing_debt_younger_than_a_year.reload.status
    assert_equal :awaiting_staffing, staffing_debt_awaiting_staffing.reload.status
    assert_equal :completed_staffing, staffing_debt_already_staffed.reload.status
  end

  test "preserve specific staffing debts when expiring" do
    forgiven_staffing_debt = FactoryBot.create(:staffing_debt,  due_by: Date.current - 2.years, state: :forgiven)
    converted_staffing_debt = FactoryBot.create(:staffing_debt, due_by: Date.current - 2.years, state: :converted)
    expired_staffing_debt = FactoryBot.create(:staffing_debt,   due_by: Date.current - 2.years, state: :expired)
    staffed_staffing_debt = FactoryBot.create(:staffing_debt,   due_by: Date.current - 2.years, state: :normal, with_staffing_job: true)

    Tasks::Logic::Debt.expire_outdated_debt

    assert_equal "forgiven", forgiven_staffing_debt.reload.state
    assert_equal "converted", converted_staffing_debt.reload.state
    assert_equal "expired", expired_staffing_debt.reload.state
    assert_equal "normal", staffed_staffing_debt.reload.state
  end

  test "expire outdated debt should remove maintenance debts older than a year but preserve younger debts" do
    maintenance_debt_older_than_a_year = FactoryBot.create(:maintenance_debt, due_by: Date.current - 365.days)
    maintenance_debt_younger_than_a_year = FactoryBot.create(:maintenance_debt, due_by: Date.current - 364.days)

    # Attended is taken care of by the preserve test.
    Tasks::Logic::Debt.expire_outdated_debt

    assert_equal :expired, maintenance_debt_older_than_a_year.reload.status
    assert_equal :causing_debt, maintenance_debt_younger_than_a_year.reload.status
  end

  test "preserve specific maintenance debts when expiring" do
    forgiven_maintenance_debt = FactoryBot.create(:maintenance_debt,  due_by: Date.current - 2.years, state: :forgiven)
    converted_maintenance_debt = FactoryBot.create(:maintenance_debt, due_by: Date.current - 2.years, state: :converted)
    expired_maintenance_debt = FactoryBot.create(:maintenance_debt,   due_by: Date.current - 2.years, state: :expired)
    attended_maintenance_debt = FactoryBot.create(:maintenance_debt,  due_by: Date.current - 2.years, state: :normal, with_attendance: true)

    Tasks::Logic::Debt.expire_outdated_debt

    assert_equal "forgiven", forgiven_maintenance_debt.reload.state
    assert_equal "converted", converted_maintenance_debt.reload.state
    assert_equal "expired", expired_maintenance_debt.reload.state
    assert_equal "normal", attended_maintenance_debt.reload.state
    assert_equal :completed, attended_maintenance_debt.reload.status
  end

  test "Should handle SMTP errors gracefully when notifying debtors" do
    # Create debtors that will trigger notifications
    successful_debt = FactoryBot.create(:overdue_maintenance_debt, due_by: Date.current.advance(days: -1))
    failing_debt = FactoryBot.create(:overdue_staffing_debt, due_by: Date.current.advance(days: -1))

    # Mock the mailer to raise an error for the failing user
    original_method = DebtMailer.method(:mail_debtor)
    DebtMailer.define_singleton_method(:mail_debtor) do |user, new_debtor|
      if user.id == failing_debt.user.id
        # Create a message delivery that will raise SMTP error
        message = original_method.call(user, new_debtor)
        message.define_singleton_method(:deliver_now) do
          raise Net::SMTPServerBusy.new("450 Message not queued: recipient is suppressed")
        end
        message
      else
        original_method.call(user, new_debtor)
      end
    end

    begin
      # Capture log output to verify error logging
      original_logger = Rails.logger
      log_output = StringIO.new
      Rails.logger = Logger.new(log_output)

      # Should not fail entirely even though one email fails
      assert_nothing_raised do
        Tasks::Logic::Debt.notify_debtors
      end

      # Verify error was logged
      log_content = log_output.string
      assert_includes log_content, "Failed to send debt notification"
      assert_includes log_content, "450 Message not queued: recipient is suppressed"

      Rails.logger = original_logger
    ensure
      # Restore original method
      DebtMailer.define_singleton_method(:mail_debtor, original_method)
    end
  end

  test "Should handle SMTP errors for reminder emails" do
    # Create long-time debtor that will trigger reminder
    old_debt = FactoryBot.create(:overdue_maintenance_debt, due_by: Date.current.advance(days: -20))
    FactoryBot.create(:initial_debt_notification, user: old_debt.user, sent_on: Date.current.advance(days: -20))

    # Mock the mailer to raise an error for reminder emails
    original_method = DebtMailer.method(:mail_debtor)
    DebtMailer.define_singleton_method(:mail_debtor) do |user, new_debtor|
      message = original_method.call(user, new_debtor)
      if !new_debtor # This is a reminder
        message.define_singleton_method(:deliver_now) do
          raise Net::SMTPFatalError.new("550 Invalid recipient")
        end
      end
      message
    end

    begin
      # Capture log output
      original_logger = Rails.logger
      log_output = StringIO.new
      Rails.logger = Logger.new(log_output)

      # Should not fail entirely even though reminder email fails
      assert_nothing_raised do
        Tasks::Logic::Debt.notify_debtors
      end

      # Verify error was logged for reminder
      log_content = log_output.string
      assert_includes log_content, "Failed to send debt reminder"
      assert_includes log_content, "550 Invalid recipient"

      Rails.logger = original_logger
    ensure
      # Restore original method
      DebtMailer.define_singleton_method(:mail_debtor, original_method)
    end
  end
end
