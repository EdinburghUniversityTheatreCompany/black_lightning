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

  test "attendees_for_form groups a user's attendances into one row carrying the credit count" do
    session = MaintenanceSession.create!(date: Date.current)
    user = users(:member)
    3.times { session.maintenance_attendances.create!(user: user) }

    lines = session.attendees_for_form

    assert_equal 1, lines.size
    assert_equal user.id, lines.first.user_id
    assert_equal 3, lines.first.quantity
  end
end
