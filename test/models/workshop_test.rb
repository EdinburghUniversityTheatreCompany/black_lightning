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

class WorkshopTest < ActiveSupport::TestCase
  include AcademicYearHelper

  test "debt_configuration_active? works for workshops" do
    workshop = FactoryBot.create(:workshop)

    assert_not workshop.debt_configuration_active?

    workshop.update!(staffing_debt_amount: 2)

    assert workshop.debt_configuration_active?
  end

  test "sync_debts_for_all_users works for workshops" do
    due_by = Date.current
    # Create workshop without debt configuration first
    workshop = FactoryBot.create(:workshop,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 2
    )

    # Now set the debt configuration
    workshop.update!(staffing_debt_start: due_by, staffing_debt_amount: 1)

    assert_difference("Admin::StaffingDebt.count", workshop.users.count) do
      workshop.sync_debts_for_all_users
    end

    workshop.users.each do |user|
      assert_equal 1, user.admin_staffing_debts.where(show: workshop).count
    end
  end

  test "assistant position rules work for workshops" do
    due_by = Date.current
    workshop = FactoryBot.create(:workshop,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      staffing_debt_start: due_by,
      staffing_debt_amount: 3
    )
    user = FactoryBot.create(:user)
    FactoryBot.create(:team_member, teamwork: workshop, user: user, position: "Assistant Facilitator")

    workshop.sync_debts_for_all_users

    # Assistant positions capped at 1
    assert_equal 1, user.admin_staffing_debts.where(show: workshop).count
  end
end
