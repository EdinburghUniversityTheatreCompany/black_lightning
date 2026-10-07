require "test_helper"

class AlertComponentTest < ViewComponent::TestCase
  test "renders its content in its type's style" do
    render_inline(AlertComponent.new(type: :danger)) { "Something went wrong" }
    assert_selector "[class*='bg-danger']", text: "Something went wrong"
  end

  test "defaults to info when type unknown" do
    render_inline(AlertComponent.new(type: :unknown)) { "Msg" }
    assert_selector "[class*='bg-info']"
  end
end
