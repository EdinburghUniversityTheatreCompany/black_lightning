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

  test "debt_configuration_active? when either amount is set" do
    assert_not FactoryBot.create(:show).debt_configuration_active?
    assert FactoryBot.create(:show, maintenance_debt_amount: 1).debt_configuration_active?
    assert FactoryBot.create(:show, staffing_debt_amount: 2).debt_configuration_active?
  end

  test "setting debt amounts to 0 converts to nil" do
    show = FactoryBot.create(:show, maintenance_debt_amount: 2, staffing_debt_amount: 3)

    show.update!(maintenance_debt_amount: 0, staffing_debt_amount: 0)

    assert_nil show.maintenance_debt_amount
    assert_nil show.staffing_debt_amount
    assert_not show.debt_configuration_active?
  end

  test "sync_debts_for_all_users creates each member's debts once, and tops up a raised amount" do
    show = create_show_with_directors
    show.update!(maintenance_debt_start: Date.current, maintenance_debt_amount: 1,
                 staffing_debt_start: Date.current, staffing_debt_amount: 1)

    assert_difference({ "Admin::MaintenanceDebt.count" => 3, "Admin::StaffingDebt.count" => 3 }) do
      show.sync_debts_for_all_users
    end
    assert_no_difference([ "Admin::MaintenanceDebt.count", "Admin::StaffingDebt.count" ]) do
      show.sync_debts_for_all_users
    end

    show.update!(staffing_debt_amount: 2)
    assert_difference("Admin::StaffingDebt.count", 3) { show.sync_debts_for_all_users }
    assert_equal Date.current, show.users.first.admin_maintenance_debts.where(show: show).sole.due_by
  end

  test "sync_debts_for_all_users does nothing for a show outside the academic year" do
    show = create_show_with_directors
    show.update!(start_date: Date.current.advance(years: -2), end_date: Date.current.advance(years: -2),
                 maintenance_debt_start: Date.current, maintenance_debt_amount: 1)

    assert_no_difference("Admin::MaintenanceDebt.count") { show.sync_debts_for_all_users }
  end

  test "staffing debts follow the position rules" do
    { "Assistant Director" => 1, "Assistant Director / Assistant Producer" => 1,
      "Director / Assistant Producer" => 3, "Welfare Contact" => 0,
      "Welfare Contact / Producer" => 3 }.each do |position, expected|
      show = FactoryBot.create(:show, start_date: start_of_year, end_date: start_of_year.advance(days: 5),
                                      staffing_debt_start: Date.current, staffing_debt_amount: 3)
      user = FactoryBot.create(:user)
      FactoryBot.create(:team_member, teamwork: show, user: user, position: position)

      show.sync_debts_for_all_users

      assert_equal expected, user.admin_staffing_debts.where(show: show).count, position
    end
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

  test "tag_debt_recommendations returns recommendations from tags" do
    show = FactoryBot.create(:show)
    show.event_tags << event_tags(:mainterm)

    recommendations = show.tag_debt_recommendations

    assert_equal 1, recommendations.length
    assert_equal "Mainterm.", recommendations.first[:tag_name]
    assert_equal 1, recommendations.first[:maintenance]
    assert_equal 2, recommendations.first[:staffing]
  end

  test "tag_debt_recommendations returns empty array when tags have no recommendations" do
    show = FactoryBot.create(:show)
    show.event_tags << event_tags(:new_writing)

    assert_empty show.tag_debt_recommendations
  end

  test "debt_recommendation_status" do
    { [ [], nil, nil ] => :no_recommendation,
      [ [ :mainterm ], nil, nil ] => :needs_config,
      [ [ :mainterm ], 1, 2 ] => :matches,
      [ [ :mainterm ], 2, 3 ] => :mismatch }.each do |(tags, maintenance, staffing), expected|
      show = FactoryBot.create(:show, maintenance_debt_amount: maintenance, staffing_debt_amount: staffing)
      show.event_tags << tags.map { |tag| event_tags(tag) }

      assert_equal expected, show.debt_recommendation_status
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

  private

  # Members are added before any debt configuration, so their after_create sync
  # creates nothing.
  def create_show_with_directors
    show = FactoryBot.create(:show, start_date: start_of_year, end_date: start_of_year.advance(days: 5))
    3.times { FactoryBot.create(:team_member, teamwork: show, user: FactoryBot.create(:user), position: "Director") }
    show
  end
end
