require "test_helper"
require "rake"

# Tests the debt rake tasks.
class TechieTaskTest < ActiveSupport::TestCase
  test "should get interaction" do
    assert_difference "Techie.count", 4 do
      Tasks::Logic::Techie.import("test/techies_test.csv")
    end

    assert "Clara Cucumber", Techie.first.children.first.name
  end
end
