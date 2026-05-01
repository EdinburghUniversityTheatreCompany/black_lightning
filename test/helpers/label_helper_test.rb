require "test_helper"

class LabelHelperTest < ActionView::TestCase
  test "sanitizes html" do
    message = "<faketag>Finbar<div> the <p></p>Viking"
    label = generate_label("bg-info", message)
    assert_equal '<span class="badge bg-info text-dark">Finbar<div> the <p></p>Viking</div></span>', label
  end

  test "returns label" do
    label = generate_label("bg-danger", "It's dangerous to go alone!")
    assert_equal '<span class="badge bg-danger">It\'s dangerous to go alone!</span>', label
  end

  test "returns label with float-right" do
    label = generate_label("bg-success", "You did it!", true)
    assert_equal '<span class="badge bg-success float-right">You did it!</span>', label
  end

  test "bg-warning gets text-dark class" do
    label = generate_label("bg-warning", "Watch out!")
    assert_equal '<span class="badge bg-warning text-dark">Watch out!</span>', label
  end

  test "bg-light gets text-dark class" do
    label = generate_label("bg-light", "Light label")
    assert_equal '<span class="badge bg-light text-dark">Light label</span>', label
  end

  test "bg-info gets text-dark class" do
    label = generate_label("bg-info", "Info label")
    assert_equal '<span class="badge bg-info text-dark">Info label</span>', label
  end

  test "rounded adds rounded-pill class" do
    label = generate_label("bg-danger", "Rounded!", false, true)
    assert_equal '<span class="badge bg-danger rounded-pill">Rounded!</span>', label
  end

  test "pull_right and rounded can be combined" do
    label = generate_label("bg-success", "Both!", true, true)
    assert_equal '<span class="badge bg-success rounded-pill float-right">Both!</span>', label
  end

  test "nil label_class produces badge with no extra class" do
    label = generate_label(nil, "No class")
    assert_equal '<span class="badge ">No class</span>', label
  end
end
