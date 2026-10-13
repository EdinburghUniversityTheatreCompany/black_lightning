require "application_system_test_case"

class KonamiCodeTest < ApplicationSystemTestCase
  KONAMI_SEQUENCE = [
    :arrow_up, :arrow_up, :arrow_down, :arrow_down,
    :arrow_left, :arrow_right, :arrow_left, :arrow_right,
    "b", "a"
  ].freeze

  test "konami code shows the unicorn on the public and admin sites" do
    login_as users(:admin)

    [ root_path, admin_path ].each do |path|
      visit path
      find("body").send_keys(*KONAMI_SEQUENCE)

      assert has_selector?(".__itify_head", wait: 3), "no unicorn on #{path}"
    end
  end
end
