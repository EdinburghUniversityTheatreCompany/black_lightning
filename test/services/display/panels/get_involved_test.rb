require "test_helper"

class Display::Panels::GetInvolvedTest < ActiveSupport::TestCase
  fixtures :opportunities, :opportunity_roles

  # The fixtures contain no "No Opportunities" block.
  test "is unavailable when nothing is open and no empty-state copy exists" do
    # Children first: delete_all bypasses dependent: :destroy.
    OpportunityRole.delete_all
    Opportunity.delete_all

    assert_not Admin::EditableBlock.exists?(name: Display::Panels::GetInvolved::EMPTY_STATE_BLOCK)
    assert_not Display::Panels::GetInvolved.new.available?
  end

  test "is available with nothing open when the site's empty-state copy exists" do
    OpportunityRole.delete_all
    Opportunity.delete_all
    Admin::EditableBlock.create!(name: Display::Panels::GetInvolved::EMPTY_STATE_BLOCK,
                                 admin_page: false, content: "Nothing right now.")

    panel = Display::Panels::GetInvolved.new

    assert panel.available?, "the slot should keep its identity rather than becoming another page"
    assert_empty panel.locals[:opportunities]
  end

  test "lists only active opportunities, capped at five" do
    panel = Display::Panels::GetInvolved.new

    assert panel.available?
    assert_equal 5, panel.locals[:opportunities].size
    assert panel.locals[:opportunities].all?(&:active?), "every listed opportunity should be active"
  end
end
