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
end
