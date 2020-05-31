require 'test_helper'

class WorkshopCounterTest < ActionView::TestCase
  test 'get workshop count' do
    FactoryBot.create_list(:workshop, 2, is_public: true, end_date: Date.today.advance(days: 1))
    FactoryBot.create :workshop, end_date: Date.today.advance(days: -1)
    FactoryBot.create :workshop, is_public: false
    assert_equal 2, WorkshopCounter.workshop_count
  end
end
