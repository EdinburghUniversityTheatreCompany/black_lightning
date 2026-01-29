# == Schema Information
#
# Table name: events
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *name*::                   <tt>string(255)</tt>
# *tagline*::                <tt>string(255)</tt>
# *slug*::                   <tt>string(255)</tt>
# *publicity_text*::         <tt>text(65535)</tt>
# *members_only_text*::      <tt>text(65535)</tt>
# *xts_id*::                 <tt>integer</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *is_public*::              <tt>boolean</tt>
# *image_file_name*::        <tt>string(255)</tt>
# *image_content_type*::     <tt>string(255)</tt>
# *image_file_size*::        <tt>integer</tt>
# *image_updated_at*::       <tt>datetime</tt>
# *start_date*::             <tt>date</tt>
# *end_date*::               <tt>date</tt>
# *venue_id*::               <tt>integer</tt>
# *season_id*::              <tt>integer</tt>
# *author*::                 <tt>string(255)</tt>
# *type*::                   <tt>string(255)</tt>
# *price*::                  <tt>string(255)</tt>
# *spark_seat_slug*::        <tt>string(255)</tt>
# *maintenance_debt_start*:: <tt>date</tt>
# *staffing_debt_start*::    <tt>date</tt>
# *proposal_id*::            <tt>integer</tt>
#--
# == Schema Information End
#++
require "test_helper"

class ShowTest < ActiveSupport::TestCase
  include AcademicYearHelper

  test "can convert show" do
    show = FactoryBot.create(:show, review_count: 0, feedback_count: 0)

    assert show.can_convert?
  end

  test "convert show with reviews and no feedbacks" do
    show = FactoryBot.create(:show, review_count: 1, feedback_count: 0)

    assert show.can_convert?
  end

  test "cannot convert show with feedbacks" do
    feedback = FactoryBot.create(:feedback)
    show = feedback.show
    show.reviews.clear

    assert_not show.can_convert?
  end

  test "debt_configuration_active? returns false when no amounts set" do
    show = FactoryBot.create(:show)

    assert_not show.debt_configuration_active?
  end

  test "debt_configuration_active? returns true when maintenance amount set" do
    show = FactoryBot.create(:show, maintenance_debt_amount: 1)

    assert show.debt_configuration_active?
  end

  test "debt_configuration_active? returns true when staffing amount set" do
    show = FactoryBot.create(:show, staffing_debt_amount: 2)

    assert show.debt_configuration_active?
  end

  test "setting debt amounts to 0 converts to nil" do
    show = FactoryBot.create(:show, maintenance_debt_amount: 2, staffing_debt_amount: 3)

    show.update!(maintenance_debt_amount: 0, staffing_debt_amount: 0)

    assert_nil show.maintenance_debt_amount
    assert_nil show.staffing_debt_amount
    assert_not show.debt_configuration_active?
  end

  test "sync_debts_for_all_users creates maintenance debts" do
    due_by = Date.current
    # Create show without debt configuration first, so team members don't get auto-debts
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5)
    )

    # Now set the debt configuration
    show.update!(maintenance_debt_start: due_by, maintenance_debt_amount: 1)

    assert_difference("Admin::MaintenanceDebt.count", show.users.count) do
      show.sync_debts_for_all_users
    end

    show.users.each do |user|
      maintenance_debts = user.admin_maintenance_debts.where(show: show)
      assert_equal 1, maintenance_debts.count
      assert_equal due_by, maintenance_debts.first.due_by
    end
  end

  test "sync_debts_for_all_users does not create duplicate debts" do
    due_by = Date.current
    # Create show without debt configuration first
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5)
    )

    show.update!(maintenance_debt_start: due_by, maintenance_debt_amount: 1)
    show.sync_debts_for_all_users

    # Syncing again should not create more debts
    assert_no_difference("Admin::MaintenanceDebt.count") do
      show.sync_debts_for_all_users
    end

    show.users.each do |user|
      assert_equal 1, user.admin_maintenance_debts.where(show: show).count
    end
  end

  test "sync_debts_for_all_users creates staffing debts" do
    due_by = Date.current
    # Create show without debt configuration and with known team members
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0
    )
    # Add 3 users with Director position (not capped)
    3.times do
      user = FactoryBot.create(:user)
      FactoryBot.create(:team_member, teamwork: show, user: user, position: "Director")
    end

    show.update!(staffing_debt_start: due_by, staffing_debt_amount: 2)

    assert_difference("Admin::StaffingDebt.count", show.users.count * 2) do
      show.sync_debts_for_all_users
    end

    show.users.each do |user|
      assert_equal 2, user.admin_staffing_debts.where(show: show).count
    end
  end

  test "sync_debts_for_all_users tops up to configured amount" do
    due_by = Date.current
    # Create show without debt configuration and with 3 known team members
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0
    )
    # Add 3 users with Director position (not capped)
    3.times do
      user = FactoryBot.create(:user)
      FactoryBot.create(:team_member, teamwork: show, user: user, position: "Director")
    end

    show.update!(staffing_debt_start: due_by, staffing_debt_amount: 1)
    show.sync_debts_for_all_users

    show.users.each do |user|
      assert_equal 1, user.admin_staffing_debts.where(show: show).count
    end

    # Increase the amount
    show.update!(staffing_debt_amount: 2)

    assert_difference("Admin::StaffingDebt.count", show.users.count) do
      show.sync_debts_for_all_users
    end

    show.users.each do |user|
      assert_equal 2, user.admin_staffing_debts.where(show: show).count
    end
  end

  test "sync_debts_for_all_users does not run for shows outside academic year" do
    # Create a show from last year
    show = FactoryBot.create(:show,
      start_date: Date.current.advance(years: -2),
      end_date: Date.current.advance(years: -2),
      maintenance_debt_start: Date.current,
      maintenance_debt_amount: 1
    )

    assert_no_difference("Admin::MaintenanceDebt.count") do
      show.sync_debts_for_all_users
    end
  end

  test "sync_debts_for_user creates debts for single user" do
    due_by = Date.current
    # Create show without debt configuration and without team members
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0
    )
    # Add a user with a known position (Director)
    user = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: show, user: user, position: "Director")

    # Now set the debt configuration
    show.update!(
      maintenance_debt_start: due_by,
      maintenance_debt_amount: 1,
      staffing_debt_start: due_by,
      staffing_debt_amount: 2
    )

    result = show.sync_debts_for_user(user)

    assert_equal 1, result[:maintenance]
    assert_equal 2, result[:staffing]
    assert_equal 1, user.admin_maintenance_debts.where(show: show).count
    assert_equal 2, user.admin_staffing_debts.where(show: show).count
  end

  test "staffing debt amount for assistant is capped at 1" do
    due_by = Date.current
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      staffing_debt_start: due_by,
      staffing_debt_amount: 3
    )
    user = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: show, user: user, position: "Assistant Director")

    show.sync_debts_for_all_users

    assert_equal 1, user.admin_staffing_debts.where(show: show).count
  end

  test "staffing debt amount for mixed assistant role is not capped" do
    due_by = Date.current
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      staffing_debt_start: due_by,
      staffing_debt_amount: 3
    )
    user = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: show, user: user, position: "Director / Assistant Producer")

    show.sync_debts_for_all_users

    # Not all roles are assistant, so full amount
    assert_equal 3, user.admin_staffing_debts.where(show: show).count
  end

  test "staffing debt amount for all assistant roles is capped" do
    due_by = Date.current
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      staffing_debt_start: due_by,
      staffing_debt_amount: 3
    )
    user = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: show, user: user, position: "Assistant Director / Assistant Producer")

    show.sync_debts_for_all_users

    # All roles are assistant, so capped at 1
    assert_equal 1, user.admin_staffing_debts.where(show: show).count
  end

  test "welfare contact gets zero staffing debts" do
    due_by = Date.current
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      staffing_debt_start: due_by,
      staffing_debt_amount: 3
    )
    user = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: show, user: user, position: "Welfare Contact")

    show.sync_debts_for_all_users

    assert_equal 0, user.admin_staffing_debts.where(show: show).count
  end

  test "welfare contact with other role gets full debts" do
    due_by = Date.current
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      staffing_debt_start: due_by,
      staffing_debt_amount: 3
    )
    user = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: show, user: user, position: "Welfare Contact / Producer")

    show.sync_debts_for_all_users

    # Has other role, so full amount
    assert_equal 3, user.admin_staffing_debts.where(show: show).count
  end

  test "cannot add user to the same show twice as team member" do
    show = FactoryBot.create(:show, team_member_count: 1)
    current_team_member = show.team_members.first

    assert_no_difference("TeamMember.count") do
      assert_raises ActiveRecord::RecordInvalid do
        show.team_members.create!(user: current_team_member.user)
      end
    end
  end

  test "as_json" do
    show = FactoryBot.create(:show, venue: venues(:one), season: FactoryBot.create(:season))

    json = show.as_json(include: [ :season ])

    assert json.is_a? Hash
    assert json.key? "venue"
    assert json.key? "season"
    assert json.key? "reviews"
  end
end
