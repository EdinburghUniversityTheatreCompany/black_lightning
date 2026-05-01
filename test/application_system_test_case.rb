require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: {
    args: %w[--no-sandbox --disable-dev-shm-usage --disable-gpu]
  }
  include Warden::Test::Helpers

  # Select a value in a Tom Select widget by visible text.
  # Tom Select hides the native <select> and rewrites the label's `for` attribute
  # to point at its own control element (suffix "-ts-control"). We strip that
  # suffix to get back to the original select ID, then call setValue via JS.
  def tom_select(text, from:)
    label = find("label", text: from)
    select_id = label["for"].sub(/-ts-control$/, "")
    option_value = evaluate_script(
      "Array.from(document.getElementById('#{select_id}').options).find(o => o.text.trim() === '#{text.gsub("'", "\\'")}')?.value"
    )
    raise "tom_select: option '#{text}' not found in select '#{select_id}'" if option_value.nil?
    execute_script("document.getElementById('#{select_id}').tomselect.setValue('#{option_value}')")
  end
end
