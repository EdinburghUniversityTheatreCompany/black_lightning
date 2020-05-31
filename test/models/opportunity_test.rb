require 'test_helper'

class Admin::OpportunityTest < ActionView::TestCase
  test 'active?' do
    opportunity = FactoryBot.create(:opportunity, approved: false, expiry_date: Date.today.advance(days: -1))

    assert_not opportunity.active?
    opportunity.approved = true

    assert_not opportunity.active?
    opportunity.expiry_date = Date.today.advance(days: 1)

    assert opportunity.active?
    opportunity.approved = false

    assert_not opportunity.active?
  end

  test 'should return the correct css class' do
    opportunity = FactoryBot.create :opportunity, expiry_date: Date.today.advance(days: -1)

    assert_equal '', opportunity.css_class

    opportunity.expiry_date = Date.today.advance(days: 1)
    opportunity.approved = false

    assert_equal 'class="error"'.html_safe, opportunity.css_class

    opportunity.approved = true

    assert_equal 'class="success"'.html_safe, opportunity.css_class
  end
end