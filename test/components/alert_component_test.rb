require "test_helper"

class AlertComponentTest < ViewComponent::TestCase
  test "renders content" do
    render_inline AlertComponent.new(type: :danger) do
      "Something went wrong"
    end
    assert_text "Something went wrong"
  end

  test "renders with danger classes" do
    render_inline AlertComponent.new(type: :danger) do
      "Error"
    end
    assert_selector "[class*='bg-danger']"
    assert_selector "[class*='text-danger']"
  end

  test "renders with success classes" do
    render_inline AlertComponent.new(type: :success) do
      "Done"
    end
    assert_selector "[class*='bg-success']"
    assert_selector "[class*='text-success']"
  end

  test "renders with warning classes" do
    render_inline AlertComponent.new(type: :warning) do
      "Watch out"
    end
    assert_selector "[class*='bg-warning']"
  end

  test "renders with info classes" do
    render_inline AlertComponent.new(type: :info) do
      "Note"
    end
    assert_selector "[class*='bg-info']"
  end

  test "defaults to info when type unknown" do
    render_inline AlertComponent.new(type: :unknown) do
      "Msg"
    end
    assert_selector "[class*='bg-info']"
  end
end
