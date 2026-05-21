require "test_helper"

class ButtonComponentTest < ViewComponent::TestCase
  test "renders as link when href given" do
    render_inline ButtonComponent.new(href: "/foo", variant: :primary).with_content("Click")
    assert_selector "a[href='/foo']", text: "Click"
    assert_no_selector "button"
  end

  test "renders as button when no href" do
    render_inline ButtonComponent.new(variant: :primary).with_content("Click")
    assert_selector "button", text: "Click"
    assert_no_selector "a"
  end

  test "primary variant applies correct classes" do
    render_inline ButtonComponent.new(href: "/foo", variant: :primary).with_content("X")
    assert_selector "a.text-primary"
    assert_selector "a.border-primary"
  end

  test "danger variant applies correct classes" do
    render_inline ButtonComponent.new(href: "/foo", variant: :danger).with_content("X")
    assert_selector "a.bg-danger"
    assert_selector "a.text-white"
  end

  test "sm size applies text-xs" do
    render_inline ButtonComponent.new(href: "/foo", size: :sm).with_content("X")
    assert_selector "a.text-xs"
  end

  test "lg size applies text-base" do
    render_inline ButtonComponent.new(href: "/foo", size: :lg).with_content("X")
    assert_selector "a.text-base"
  end

  test "disabled button gets disabled attribute" do
    render_inline ButtonComponent.new(disabled: true).with_content("X")
    assert_selector "button[disabled]"
  end

  test "classes_for returns string for primary md" do
    classes = ButtonComponent.classes_for(variant: :primary)
    assert_includes classes, "text-primary"
    assert_includes classes, "border-primary"
  end

  test "classes_for returns string for danger sm" do
    classes = ButtonComponent.classes_for(variant: :danger, size: :sm)
    assert_includes classes, "bg-danger"
    assert_includes classes, "text-xs"
  end

  test "passes extra html_options through" do
    render_inline ButtonComponent.new(href: "/foo", title: "My title").with_content("X")
    assert_selector "a[title='My title']"
  end
end
