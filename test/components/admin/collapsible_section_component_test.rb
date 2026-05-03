require "test_helper"

class Admin::CollapsibleSectionComponentTest < ViewComponent::TestCase
  test "renders title in toggle button" do
    render_inline Admin::CollapsibleSectionComponent.new(title: "My Section") { "Content" }
    assert_selector "button", text: /My Section/
  end

  test "starts collapsed by default" do
    render_inline Admin::CollapsibleSectionComponent.new(title: "My Section") { "Content" }
    assert_selector "[data-collapsible-target='content'].hidden"
  end

  test "starts open when start_open is true" do
    render_inline Admin::CollapsibleSectionComponent.new(title: "My Section", start_open: true) { "Content" }
    assert_no_selector "[data-collapsible-target='content'].hidden"
  end

  test "renders title_right content" do
    render_inline Admin::CollapsibleSectionComponent.new(title: "My Section", title_right: "<span class='extra'>!</span>".html_safe) { "Content" }
    assert_selector "span.extra"
  end
end
