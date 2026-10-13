require "application_system_test_case"

# The toast stream action shows its message as text unless the stream carries `html`: the
# messages interpolate user-editable names.
class ToastStreamTest < ApplicationSystemTestCase
  test "a toast message is rendered as text, not markup" do
    login_as users(:admin)
    visit admin_path

    page.execute_script(<<~JS)
      Turbo.renderStreamMessage('<turbo-stream action="toast" type="success" message="&lt;b&gt;x&lt;/b&gt;"></turbo-stream>')
    JS

    assert_selector ".swal2-container", text: "<b>x</b>"
    assert_no_selector ".swal2-container b"
  end
end
