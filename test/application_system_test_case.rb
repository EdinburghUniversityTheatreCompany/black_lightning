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

  def tom_select(text, from:) = tom_select_call("setValue", text, from)

  # For multiple selects: setValue replaces every choice, addItem adds one.
  def tom_select_add(text, from:) = tom_select_call("addItem", text, from)

  private

  # Tom Select rewrites the label's `for` to its own "-ts-control" element.
  def tom_select_call(method, text, from)
    select_id = find("label", text: from)["for"].delete_suffix("-ts-control")
    value = evaluate_script("Array.from(document.getElementById(arguments[0]).options).find(o => o.text.trim() === arguments[1])?.value", select_id, text)
    raise "tom_select: option '#{text}' not found in select '#{select_id}'" if value.nil?

    execute_script("document.getElementById(arguments[0]).tomselect.#{method}(arguments[1])", select_id, value)
  end
end
