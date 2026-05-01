require "test_helper"

class Admin::PageHeaderComponentTest < ViewComponent::TestCase
  test "renders title" do
    render_inline Admin::PageHeaderComponent.new(title: "Test Page")
    assert_selector "h1", text: "Test Page"
  end

  test "renders badges when present" do
    render_inline Admin::PageHeaderComponent.new(
      title: "Test",
      header_badges: [ { label_class: "bg-success", text: "Active" } ]
    )
    assert_selector ".badge", text: "Active"
  end

  test "renders no badges when list is empty" do
    render_inline Admin::PageHeaderComponent.new(title: "Test", header_badges: [])
    assert_no_selector ".badge"
  end
end
