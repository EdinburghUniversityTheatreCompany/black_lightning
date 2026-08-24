require "test_helper"

class Display::Panels::GetInvolvedTest < ActiveSupport::TestCase
  fixtures :opportunities, :opportunity_roles

  test "is unavailable when nothing is open" do
    # opportunity_roles has no cascading FK, and delete_all bypasses the
    # model's dependent: :destroy -- children must go first, matching
    # empty_the_database! in pages_controller_test.rb.
    OpportunityRole.delete_all
    Opportunity.delete_all

    assert_not Display::Panels::GetInvolved.new.available?
  end

  test "lists only active opportunities, capped at five" do
    panel = Display::Panels::GetInvolved.new

    assert panel.available?
    assert_operator panel.locals[:opportunities].size, :<=, 5
    assert panel.locals[:opportunities].all?(&:active?), "every listed opportunity should be active"
  end
end
