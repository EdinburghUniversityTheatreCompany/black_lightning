require "test_helper"

class Display::Panels::GetInvolvedTest < ActiveSupport::TestCase
  fixtures :opportunities, :opportunity_roles

  # The fixtures deliberately contain no "No Opportunities" block, so these two
  # tests exercise the with-copy and without-copy halves of `available?`.
  test "is unavailable when nothing is open and no empty-state copy exists" do
    # opportunity_roles has no cascading FK, and delete_all bypasses the
    # model's dependent: :destroy -- children must go first, matching
    # empty_the_database! in pages_controller_test.rb.
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
