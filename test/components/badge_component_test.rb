require "test_helper"

class BadgeComponentTest < ViewComponent::TestCase
  test "renders danger badge" do
    render_inline(BadgeComponent.new(type: :danger)) do
      "Unpaid"
    end
    assert_selector "span[class*='text-danger']", text: "Unpaid"
  end

  test "renders success badge" do
    render_inline(BadgeComponent.new(type: :success)) do
      "Member"
    end
    assert_selector "span[class*='text-success']", text: "Member"
  end

  test "renders warning badge" do
    render_inline(BadgeComponent.new(type: :warning)) do
      "Pending"
    end
    assert_selector "span[class*='text-warning']", text: "Pending"
  end

  test "renders secondary badge by default" do
    render_inline(BadgeComponent.new) do
      "Unknown"
    end
    assert_selector "span[class*='bg-gray-100']", text: "Unknown"
  end

  test "renders pill variant" do
    render_inline(BadgeComponent.new(type: :primary, pill: true)) do
      "42"
    end
    assert_selector "span[class*='rounded-full']"
  end

  test "renders pull_right variant" do
    render_inline(BadgeComponent.new(type: :danger, pull_right: true)) do
      "Late"
    end
    assert_selector "span[class*='float-right']"
  end
end
