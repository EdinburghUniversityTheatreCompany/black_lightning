require "test_helper"

class ButtonComponentTest < ViewComponent::TestCase
  test "renders as a link carrying its variant, size and html options when href given" do
    render_inline ButtonComponent.new(href: "/foo", variant: :danger, size: :sm, title: "My title").with_content("Click")
    assert_selector "a.bg-danger.text-xs[href='/foo'][title='My title']", text: "Click"
    assert_no_selector "button"
  end

  test "renders as button when no href" do
    render_inline ButtonComponent.new(variant: :primary).with_content("Click")
    assert_selector "button", text: "Click"
    assert_no_selector "a"
  end

  test "disabled button gets disabled attribute" do
    render_inline ButtonComponent.new(disabled: true).with_content("X")
    assert_selector "button[disabled]"
  end

  test "classes_for joins the variant and size classes" do
    classes = ButtonComponent.classes_for(variant: :danger, size: :sm)
    assert_includes classes, "bg-danger"
    assert_includes classes, "text-xs"
  end
end
