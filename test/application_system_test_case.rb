require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Undoes the parallelize inherited from ActiveSupport::TestCase. Browser
  # startup dominates these, so 8 workers measured no faster than 1.
  parallelize(workers: 1)

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_options|
    driver_options.add_argument("--no-sandbox")
    driver_options.add_argument("--disable-dev-shm-usage")
    driver_options.add_argument("--disable-gpu")
  end
  include Warden::Test::Helpers

  # Set a date input value reliably in headless Chrome.
  #
  # Chrome's <input type="date"> is segment-based (dd|mm|yyyy) and its built-in
  # required validation ignores programmatically set values (el.value = ...) —
  # it only trusts values entered via user interaction. Trying to send keystrokes
  # is also unreliable because click→send_keys has a race condition.
  #
  # Solution: set the value via JS and remove the required attribute so Chrome
  # won't block the form. Rails' own presence validation still guards the value
  # server-side — browser_validations = true is redundant for server-validated fields.
  def set_date_field(label, date)
    field_id = find_field(label)[:id]
    page.execute_script(<<~JS)
      var el = document.getElementById('#{field_id}');
      el.value = '#{date}';
      el.removeAttribute('required');
    JS
  end

  def tom_select(text, from:)
    select_id, option_value = tom_select_option(text, from: from)
    execute_script("document.getElementById('#{select_id}').tomselect.setValue('#{option_value}')")
  end

  # The MULTIPLE variant: setValue replaces every choice, addItem adds one.
  def tom_select_add(text, from:)
    select_id, option_value = tom_select_option(text, from: from)
    execute_script("document.getElementById('#{select_id}').tomselect.addItem('#{option_value}')")
  end

  private

  # Tom Select hides the native <select> and rewrites the label's `for` to its
  # own control element, hence the "-ts-control" strip.
  def tom_select_option(text, from:)
    label = find("label", text: from)
    select_id = label["for"].sub(/-ts-control$/, "")
    option_value = evaluate_script(
      "Array.from(document.getElementById('#{select_id}').options).find(o => o.text.trim() === '#{text.gsub("'", "\\'")}')?.value"
    )
    raise "tom_select: option '#{text}' not found in select '#{select_id}'" if option_value.nil?
    [ select_id, option_value ]
  end
end
