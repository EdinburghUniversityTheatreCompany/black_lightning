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
require 'test_helper'

class ShowTest < ActiveSupport::TestCase
  test 'can convert show' do
    show = FactoryBot.create(:show, review_count: 0)

    assert show.can_convert?
  end

  test 'cannot convert show with reviews' do
    show = FactoryBot.create(:show, review_count: 1)

    assert_not show.can_convert?
  end

  test 'cannot convert show with feedbacks' do
    feedback = FactoryBot.create(:feedback)
    show = feedback.show
    show.reviews.clear

    assert_not show.can_convert?
  end

  test 'create maintenance debts' do
    due_by = Date.current
    show = FactoryBot.create(:show, maintenance_debt_start: due_by)

    show.create_maintenance_debts

    show.users.each do |user|
      maintenance_debts = user.admin_maintenance_debts.where(show: show)
      assert_equal 1, maintenance_debts.count
      assert_equal due_by, maintenance_debts.first.due_by
    end

    # Test that the date changes, but the amount stays 1. 
    new_due_by = Date.current.advance(days: 5)
    show.update_attribute(:maintenance_debt_start, new_due_by)
    
    FactoryBot.create(:team_member, teamwork: show)

    # Test that the new user also gets a maintenance debt.

    show.create_maintenance_debts

    show.users.each do |user|
      maintenance_debts = user.admin_maintenance_debts.where(show: show)
      assert_equal 1, maintenance_debts.count
      assert_equal new_due_by, maintenance_debts.first.due_by
    end

    # Extra validation on the generated maintenance debt
    maintenance_debt = show.users.first.admin_maintenance_debts.first

    assert_equal new_due_by, maintenance_debt.due_by
    assert_equal show.users.first, maintenance_debt.user
    assert_equal 'unfulfilled', maintenance_debt.state
    assert_equal show, maintenance_debt.show
  end

  test 'create staffing debts' do
    due_by = Date.current
    show = FactoryBot.create(:show, staffing_debt_start: due_by)

    show.create_staffing_debts(1)

    show.users.each do |user|
      assert_equal 1, user.admin_staffing_debts.where(show: show).count
    end

    show.create_staffing_debts(1)

    show.users.each do |user|
      assert_equal 1, user.admin_staffing_debts.where(show: show).count
    end

    show.create_staffing_debts(2)

    show.users.each do |user|
      assert_equal 2, user.admin_staffing_debts.where(show: show).count
    end

    user = show.users.first
    staffing_debt = user.admin_staffing_debts.first

    assert_equal due_by, staffing_debt.due_by
    assert_equal user, staffing_debt.user
    assert_equal show, staffing_debt.show
    assert_not staffing_debt.converted
    assert_not staffing_debt.forgiven

    # Test that converted debts don't count when creating new staffing debts.

    FactoryBot.create(:staffing_debt, user: user, show: show, converted: true)

    show.create_staffing_debts(3)

    assert_equal 4, user.admin_staffing_debts.count
  end

  test 'as_json' do
    show = FactoryBot.create(:show, venue: venues(:one), season: FactoryBot.create(:season))

    json = show.as_json(include: [:season])

    assert json.is_a? Hash
    assert json.key? 'venue'
    assert json.key? 'season'
    assert json.key? 'reviews'
  end
end
