require "test_helper"

class Display::Panels::GetInvolvedTest < ActiveSupport::TestCase
  fixtures :opportunities, :opportunity_roles

  test "lists only active opportunities, capped at the limit" do
    limit = Display::Panels::GetInvolved::LIMIT
    (limit + 1).times { FactoryBot.create(:opportunity, approved: true, expiry_date: 1.month.from_now) }

    listed = Display::Panels::GetInvolved.new.locals[:opportunities]

    assert_equal limit, listed.size
    assert listed.all?(&:active?), "every listed opportunity should be active"
  end
end
