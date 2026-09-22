require "test_helper"

BASE_BADGE_CLASSES = "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"

class LabelHelperTest < ActionView::TestCase
  test "sanitizes html" do
    message = "<faketag>Finbar<div> the <p></p>Viking"
    label = generate_label("bg-info", message)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-info/15 text-info\">Finbar<div> the <p></p>Viking</div></span>", label
  end

  test "returns label" do
    label = generate_label("bg-danger", "It's dangerous to go alone!")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">It's dangerous to go alone!</span>", label
  end

  test "returns label with float-right" do
    label = generate_label("bg-success", "You did it!", true)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-success/15 text-success float-right\">You did it!</span>", label
  end

  test "bg-warning maps to semantic warning classes" do
    label = generate_label("bg-warning", "Watch out!")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-warning/15 text-warning\">Watch out!</span>", label
  end

  test "bg-light maps to gray classes" do
    label = generate_label("bg-light", "Light label")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-gray-100 text-gray-800\">Light label</span>", label
  end

  test "bg-info maps to semantic info classes" do
    label = generate_label("bg-info", "Info label")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-info/15 text-info\">Info label</span>", label
  end

  test "rounded adds rounded-full class" do
    label = generate_label("bg-danger", "Rounded!", false, true)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger rounded-full\">Rounded!</span>", label
  end

  test "pull_right and rounded can be combined" do
    label = generate_label("bg-success", "Both!", true, true)
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} bg-success/15 text-success rounded-full float-right\">Both!</span>", label
  end

  test "nil label_class produces badge with no extra class" do
    label = generate_label(nil, "No class")
    assert_equal "<span class=\"#{BASE_BADGE_CLASSES} \">No class</span>", label
  end
end
