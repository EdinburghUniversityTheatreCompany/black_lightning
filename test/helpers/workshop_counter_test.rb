require "test_helper"

class WorkshopCounterTest < ActionView::TestCase
  test "get workshop count" do
    FactoryBot.create_list(:workshop, 2, is_public: true, start_date: Date.current, end_date: Date.current.advance(days: 1))
    FactoryBot.create :workshop, start_date: Date.current.advance(days: -2), end_date: Date.current.advance(days: -1)
    FactoryBot.create :workshop, is_public: false
    assert_equal 2, WorkshopCounter.workshop_count
  end
end
