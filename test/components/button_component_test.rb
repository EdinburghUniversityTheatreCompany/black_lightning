require "test_helper"

class ButtonComponentTest < ActiveSupport::TestCase
  test "classes_for joins the variant and size classes" do
    classes = ButtonComponent.classes_for(variant: :danger, size: :sm)
    assert_includes classes, "bg-danger"
    assert_includes classes, "text-xs"
  end
end
