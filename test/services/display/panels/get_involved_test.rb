require "test_helper"

class Display::Panels::GetInvolvedTest < ActiveSupport::TestCase
  fixtures :opportunities, :opportunity_roles

  test "lists only active opportunities, capped at five" do
    panel = Display::Panels::GetInvolved.new

    assert panel.available?
    assert_equal 5, panel.locals[:opportunities].size
    assert panel.locals[:opportunities].all?(&:active?), "every listed opportunity should be active"
  end
end
