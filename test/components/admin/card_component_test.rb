require "test_helper"

class Admin::CardComponentTest < ViewComponent::TestCase
  test "renders title" do
    render_inline Admin::CardComponent.new(title: "My Card") do
      "<p>Content</p>"
    end

    assert_text "My Card"
  end

  test "renders content" do
    render_inline Admin::CardComponent.new(title: "My Card") do
      "<p>Some content</p>"
    end

    assert_text "Some content"
  end

  test "wraps content in padding div by default" do
    render_inline Admin::CardComponent.new(title: "My Card") do
      "<p>Content</p>"
    end

    assert_selector "div.p-4", text: "Content"
  end

  test "flush mode skips padding wrapper" do
    render_inline Admin::CardComponent.new(title: "My Card", flush: true) do
      "<p>Content</p>"
    end

    assert_no_selector "div.p-4"
  end

  test "applies danger variant header classes" do
    render_inline Admin::CardComponent.new(title: "My Card", variant: :danger) do
      "<p>Content</p>"
    end

    assert_selector "div.bg-red-600"
  end

  test "applies success variant header classes" do
    render_inline Admin::CardComponent.new(title: "My Card", variant: :success) do
      "<p>Content</p>"
    end

    assert_selector "div.bg-green-600"
  end
end
