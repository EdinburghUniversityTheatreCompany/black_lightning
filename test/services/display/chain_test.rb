require "test_helper"

class Display::ChainTest < ActiveSupport::TestCase
  # Anthias plays a fixed playlist forever, so a chain that resolves to nothing
  # is a blank screen in the box office. Chain appends Identity itself precisely
  # so that cannot be caused by a caller forgetting to terminate its chain.
  class NeverAvailable < Display::Panels::Base
    def available? = false
  end

  test "a chain with no panels at all resolves to the identity card" do
    assert_instance_of Display::Panels::Identity, Display::Chain.new.resolve
  end

  test "a chain of only unavailable panels resolves to the identity card" do
    chain = Display::Chain.new(NeverAvailable.new, NeverAvailable.new)

    assert_instance_of Display::Panels::Identity, chain.resolve
  end

  test "the first available panel still wins over the appended identity card" do
    chain = Display::Chain.new(NeverAvailable.new, Display::Panels::WhatsOn.new)

    FactoryBot.create(:show, is_public: true, start_date: Date.current, end_date: Date.current + 1)

    assert_instance_of Display::Panels::WhatsOn, chain.resolve
  end
end
