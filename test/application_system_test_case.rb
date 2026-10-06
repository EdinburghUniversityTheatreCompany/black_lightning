require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Undoes the inherited parallelize: browser startup dominates, so 8 workers measured no faster.
  parallelize(workers: 1)

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |driver_options|
    driver_options.add_argument("--no-sandbox")
    driver_options.add_argument("--disable-dev-shm-usage")
    driver_options.add_argument("--disable-gpu")
  end
  include Warden::Test::Helpers

  # Chrome's segmented date input ignores a programmatically set value when checking
  # `required`, and click->send_keys races. So set it by JS and drop `required`;
  # presence is still validated server-side.
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

  # For multiple selects: setValue replaces every choice, addItem adds one.
  def tom_select_add(text, from:)
    select_id, option_value = tom_select_option(text, from: from)
    execute_script("document.getElementById('#{select_id}').tomselect.addItem('#{option_value}')")
  end

  private

  # Tom Select rewrites the label's `for` to its own "-ts-control" element.
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
