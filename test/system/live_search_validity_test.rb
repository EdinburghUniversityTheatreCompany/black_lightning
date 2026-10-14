require "application_system_test_case"

# Live search fetches on every change, skipping the browser's own form check, so it asks for it
# itself: a year past an input's max shows the browser's message and searches nothing.
class LiveSearchValidityTest < ApplicationSystemTestCase
  test "a year past 9999 is reported, not searched" do
    visit "/archives/shows"

    page.execute_script(<<~JS)
      const input = document.querySelector("input[name='q[end_date_gteq]']")
      input.value = "11988-10-01"
      input.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    assert page.evaluate_script("document.querySelector('input[name=\"q[end_date_gteq]\"]').validity.rangeOverflow")
    sleep 1.5 # past the live-search delay
    assert_no_match(/end_date_gteq/, page.current_url)
  end
end
