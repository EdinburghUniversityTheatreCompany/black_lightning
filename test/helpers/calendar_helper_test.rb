require "test_helper"

class CalendarHelperTest < ActionView::TestCase
  test "google platform for gmail.com" do
    result = calendar_instructions_for("user@gmail.com")
    assert_includes result, "Google Calendar"
  end

  test "google platform for googlemail.com" do
    result = calendar_instructions_for("user@googlemail.com")
    assert_includes result, "Google Calendar"
  end

  test "microsoft platform for ed.ac.uk" do
    result = calendar_instructions_for("user@ed.ac.uk")
    assert_includes result, "Outlook"
  end

  test "microsoft platform for outlook.com" do
    result = calendar_instructions_for("user@outlook.com")
    assert_includes result, "Outlook"
  end

  test "shows all platforms for unknown domain" do
    result = calendar_instructions_for("user@randomdomain.com")
    assert_includes result, "Google Calendar"
    assert_includes result, "Outlook"
    assert_includes result, "Apple"
  end
end
