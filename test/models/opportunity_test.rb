# == Schema Information
#
# Table name: opportunities
#
# *id*::          <tt>integer, not null, primary key</tt>
# *title*::       <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *show_email*::  <tt>boolean</tt>
# *approved*::    <tt>boolean</tt>
# *creator_id*::  <tt>integer</tt>
# *approver_id*:: <tt>integer</tt>
# *expiry_date*:: <tt>date</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::OpportunityTest < ActionView::TestCase
  test "active?" do
    opportunity = FactoryBot.create(:opportunity, approved: false, expiry_date: Date.current.advance(days: -1))

    assert_not opportunity.active?
    opportunity.approved = true

    assert_not opportunity.active?
    opportunity.expiry_date = Date.current.advance(days: 1)

    assert opportunity.active?
    opportunity.approved = false

    assert_not opportunity.active?
  end

  test "email_visibility defaults to no_one" do
    opp = Opportunity.new
    assert opp.no_one?
  end

  test "email_visibility enum has correct values" do
    assert_equal 0, Opportunity.email_visibilities[:no_one]
    assert_equal 1, Opportunity.email_visibilities[:members_only]
    assert_equal 2, Opportunity.email_visibilities[:everyone]
  end

  test "contact_email is optional" do
    opp = opportunities(:active_opportunity)
    opp.contact_email = nil
    assert opp.valid?
  end

  test "contact_email validates format when present" do
    opp = opportunities(:active_opportunity)
    opp.contact_email = "not-an-email"
    assert_not opp.valid?
    assert_includes opp.errors[:contact_email], "is invalid"
  end

  test "should return the correct css class" do
    opportunity = FactoryBot.create :opportunity, expiry_date: Date.current.advance(days: -1)

    assert_equal "", opportunity.css_class

    opportunity.expiry_date = Date.current.advance(days: 1)
    opportunity.approved = false

    assert_equal "table-danger".html_safe, opportunity.css_class

    opportunity.approved = true

    assert_equal "table-success".html_safe, opportunity.css_class
  end
end
