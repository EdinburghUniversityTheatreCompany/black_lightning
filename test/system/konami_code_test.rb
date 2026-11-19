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
      wait_for_konami_controller
      find("body").send_keys(*KONAMI_SEQUENCE)

      assert has_selector?(".__itify_head", wait: 3), "no unicorn on #{path}"
    end
  end

  private

  # Keys sent before the controller connects are lost: the listener is a Stimulus action.
  # A slow CI runner (parallel workers since #560) can still be loading it after `visit`.
  def wait_for_konami_controller
    page.document.synchronize do
      connected = evaluate_script(
        "!!window.Stimulus?.getControllerForElementAndIdentifier(document.body, 'konami-code')"
      )
      raise Capybara::ExpectationNotMet, "konami-code controller never connected" unless connected
    end
  end
end
