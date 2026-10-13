require "test_helper"

class CollapsibleSectionComponentTest < ViewComponent::TestCase
  test "renders title in toggle button" do
    render_inline CollapsibleSectionComponent.new(title: "My Section") { "Content" }
    assert_selector "button", text: /My Section/
  end

  test "starts collapsed by default" do
    render_inline CollapsibleSectionComponent.new(title: "My Section") { "Content" }
    assert_selector "[data-collapsible-target='content'].hidden"
  end

  test "starts open when start_open is true" do
    render_inline CollapsibleSectionComponent.new(title: "My Section", start_open: true) { "Content" }
    assert_no_selector "[data-collapsible-target='content'].hidden"
  end
end
