
require 'test_helper'

class FormattingHelperTest < ActionView::TestCase
  test 'escape line breaks' do
    assert_equal 'Hello<br />world', escape_line_breaks("Hello\nworld"), 'Line breaks are not being escaped correctly'
  end
end