
require 'test_helper'

class FormattingHelperTest < ActionView::TestCase
  test 'escape line breaks' do
    assert_equal 'Hello<br />world', escape_line_breaks("Hello\nworld"), 'Line breaks are not being escaped correctly'
  end
  
  test 'bool_icon' do
    assert_equal '&#10004;', bool_icon(true)
    assert_equal '&#10008;', bool_icon(false)
  end

  test 'bool_text' do
    assert_equal 'Yes', bool_text(true)
    assert_equal 'yes', bool_text('Pineapple', false)
    assert_equal 'no', bool_text(false, false)
    assert_equal 'No', bool_text(nil, true)
    assert_equal 'Yes', bool_text('')
    assert_equal 'Yes', bool_text([])
  end
end