# == Schema Information
#
# Table name: maintenance_sessions
#
# *id*::         <tt>bigint, not null, primary key</tt>
# *date*::       <tt>date</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class MaintenanceSessionTest < ActiveSupport::TestCase
  test "to_label uses the name when present" do
    assert_equal "Autumn deep clean", maintenance_sessions(:named).to_label
  end

  test "to_label falls back to the date when no name" do
    session = maintenance_sessions(:one)
    assert_nil session.name
    assert_equal session.date, session.to_label
  end

  test "clamps the requested credits to the per-attendee maximum" do
    session = MaintenanceSession.new(date: Date.current)
    over_max = MaintenanceSession::MAX_CREDITS_PER_ATTENDEE + 50

    # Assign without saving: the cap is enforced as records are built in memory.
    session.maintenance_credits_attributes = { "0" => { user_id: users(:member).id, quantity: over_max.to_s } }

    assert_equal MaintenanceSession::MAX_CREDITS_PER_ATTENDEE, session.maintenance_credits.size
  end

  test "a bulk credit grant matches the user's debts once and leaves no suppression leakage" do
    user = users(:member)
    3.times { FactoryBot.create(:maintenance_debt, user: user) }

    session = MaintenanceSession.create!(date: Date.current,
      maintenance_credits_attributes: { "0" => { user_id: user.id, quantity: "3" } })

    assert_equal 3, session.maintenance_credits.count
    # Reallocation still ran (once, after the batch) and matched every debt to an attendance.
    assert_equal 3, Admin::MaintenanceDebt.where(user: user).where.not(maintenance_credit_id: nil).count
    # The thread-local suppression flag is not left set after the save.
    assert_nil User.suppress_maintenance_reallocation
  end

  test "attendees_for_form reflects unsaved built attendances (form re-render after a failed save)" do
    session = MaintenanceSession.create!(date: Date.current)
    # Assign without saving, as a failed save (e.g. blank date) would leave the form.
    session.maintenance_credits_attributes = { "0" => { user_id: users(:member).id, quantity: "2" } }

    lines = session.attendees_for_form

    assert_equal 1, lines.size
    assert_equal 2, lines.first.quantity
  end

  test "attendees_for_form groups a user's attendances into one row carrying the credit count" do
    session = MaintenanceSession.create!(date: Date.current)
    user = users(:member)
    3.times { session.maintenance_credits.create!(user: user) }

    lines = session.attendees_for_form

    assert_equal 1, lines.size
    assert_equal user.id, lines.first.user_id
    assert_equal 3, lines.first.quantity
  end
end
