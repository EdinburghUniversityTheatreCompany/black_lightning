require "application_system_test_case"

class TechieTreeTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  test "the legend shows a colour swatch for each entry year" do
    visit tree_admin_techies_path

    swatches = all("[data-techie-graph-target='legend'] span > span", visible: :all)
    assert_equal 2, swatches.size
    swatches.each do |swatch|
      assert_equal 12, evaluate_script("arguments[0].getBoundingClientRect().width", swatch)
    end
  end
end
