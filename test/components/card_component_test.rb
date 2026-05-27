require "test_helper"

class CardComponentTest < ViewComponent::TestCase
  test "renders title" do
    render_inline CardComponent.new(title: "My Card") do
      "<p>Content</p>".html_safe
    end

    assert_text "My Card"
  end

  test "renders content" do
    render_inline CardComponent.new(title: "My Card") do
      "<p>Some content</p>".html_safe
    end

    assert_text "Some content"
  end

  test "wraps content in padding div by default" do
    render_inline CardComponent.new(title: "My Card") do
      "<p>Content</p>".html_safe
    end

    assert_selector "div.p-4"
  end

  test "flush mode skips padding wrapper" do
    render_inline CardComponent.new(title: "My Card", flush: true) do
      "<p>Content</p>".html_safe
    end

    assert_no_selector "div.p-4"
  end

  test "renders without title - no header rendered" do
    render_inline CardComponent.new do
      "<p>Content</p>".html_safe
    end

    assert_no_selector "div.border-b"
    assert_text "Content"
  end

  test "renders footer slot" do
    render_inline CardComponent.new(title: "My Card") do |c|
      c.with_footer { "Footer content".html_safe }
      "<p>Body</p>".html_safe
    end

    assert_text "Footer content"
    assert_selector "div.border-t"
  end

  test "renders tools slot in header" do
    render_inline CardComponent.new(title: "My Card") do |c|
      c.with_tools { "<button>Action</button>".html_safe }
      "<p>Body</p>".html_safe
    end

    assert_selector "button", text: "Action"
  end

  test "no header rendered when no title and no tools" do
    render_inline CardComponent.new do
      "<p>Content</p>".html_safe
    end

    assert_no_selector ".border-b"
  end

  test "header rendered when no title but tools provided" do
    render_inline CardComponent.new do |c|
      c.with_tools { "<button>Tool</button>".html_safe }
      "<p>Content</p>".html_safe
    end

    assert_selector "button", text: "Tool"
  end

  test "applies danger variant header classes" do
    render_inline CardComponent.new(title: "My Card", variant: :danger) do
      "<p>Content</p>".html_safe
    end

    assert_selector "div.bg-red-600"
  end

  test "applies html_class to outer div" do
    render_inline CardComponent.new(title: "My Card", html_class: "w-fit") do
      "<p>Content</p>".html_safe
    end

    assert_selector "div.w-fit"
  end
end
