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
require 'test_helper'

class Admin::OpportunityTest < ActionView::TestCase
  test 'active?' do
    opportunity = FactoryBot.create(:opportunity, approved: false, expiry_date: Date.current.advance(days: -1))

    assert_not opportunity.active?
    opportunity.approved = true

    assert_not opportunity.active?
    opportunity.expiry_date = Date.current.advance(days: 1)

    assert opportunity.active?
    opportunity.approved = false

    assert_not opportunity.active?
  end

  test 'should return the correct css class' do
    opportunity = FactoryBot.create :opportunity, expiry_date: Date.current.advance(days: -1)

    assert_equal '', opportunity.css_class

    opportunity.expiry_date = Date.current.advance(days: 1)
    opportunity.approved = false

    assert_equal 'table-danger'.html_safe, opportunity.css_class

    opportunity.approved = true

    assert_equal 'table-success'.html_safe, opportunity.css_class
  end
end
