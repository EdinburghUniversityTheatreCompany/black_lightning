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

  test "a failed position save is logged, not thrown" do
    page.driver.browser.execute_cdp(
      "Page.addScriptToEvaluateOnNewDocument",
      source: "Storage.prototype.setItem = function () { throw new Error('quota') }"
    )

    visit tree_admin_techies_path(q: { id_eq: techies(:one).id })
    assert_selector "[data-techie-graph-target='canvas'] canvas", wait: 10

    messages = []
    20.times do
      messages += page.driver.browser.logs.get(:browser).map(&:message)
      break if messages.any? { |message| message.include?("Unable to save positions") }
      sleep 0.25
    end

    assert messages.any? { |message| message.include?("Unable to save positions") }, messages.inspect
    assert messages.none? { |message| message.include?("is not a function") }, messages.inspect
  end
end
