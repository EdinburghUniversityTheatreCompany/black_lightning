require "test_helper"

class BadgeComponentTest < ViewComponent::TestCase
  test "renders its content in its type's style" do
    render_inline(BadgeComponent.new(type: :danger)) { "Unpaid" }
    assert_selector "span[class*='text-danger']", text: "Unpaid"
  end

  test "renders secondary badge by default" do
    render_inline(BadgeComponent.new) { "Unknown" }
    assert_selector "span[class*='bg-gray-100']", text: "Unknown"
  end

  test "pill and html_class add their classes" do
    render_inline(BadgeComponent.new(type: :primary, pill: true, html_class: "ml-2")) { "42" }
    assert_selector "span.rounded-full.ml-2"
  end
end
