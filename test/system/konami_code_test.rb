require "application_system_test_case"

class KonamiCodeTest < ApplicationSystemTestCase
  KONAMI_SEQUENCE = [
    :arrow_up, :arrow_up, :arrow_down, :arrow_down,
    :arrow_left, :arrow_right, :arrow_left, :arrow_right,
    "b", "a"
  ].freeze

  test "konami code shows unicorn on public site" do
    visit root_path

    find("body").send_keys(*KONAMI_SEQUENCE)

    assert_selector ".__cornify_unicorn", wait: 3
  end

  test "konami code shows unicorn on admin site" do
    login_as users(:admin)
    visit admin_path

    find("body").send_keys(*KONAMI_SEQUENCE)

    assert_selector ".__cornify_unicorn", wait: 3
  end
end
