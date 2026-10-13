require "test_helper"

class LabelHelperTest < ActionView::TestCase
  BASE_BADGE_CLASSES = "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"

  test "sanitizes html" do
    message = "<faketag>Finbar<div> the <p></p>Viking"
    label = generate_label("bg-info", message)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-info/15 text-info\">Finbar<div> the <p></p>Viking</div></span>", label
  end

  test "maps the badge class and appends the modifiers" do
    {
      [ "bg-danger", false, false ] => "bg-danger/15 text-danger",
      [ "bg-warning", false, false ] => "bg-warning/15 text-warning",
      [ "bg-light", false, false ] => "bg-gray-100 text-gray-800",
      [ "bg-success", true, false ] => "bg-success/15 text-success float-right",
      [ "bg-danger", false, true ] => "bg-danger/15 text-danger rounded-full",
      [ "bg-success", true, true ] => "bg-success/15 text-success rounded-full float-right",
      [ nil, false, false ] => ""
    }.each do |(label_class, pull_right, rounded), mapped|
      assert_equal "<span class=\"#{BASE_BADGE_CLASSES} #{mapped}\">Text</span>", generate_label(label_class, "Text", pull_right, rounded)
    end
  end
end
