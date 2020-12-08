require 'test_helper'

class CookieHelperTest < ActionView::TestCase
  test 'Sets cookie and deletes cookie' do
    name = 'Hexagon'
    value = 'I desire a pineapple'

    set_cookie(name, value)

    assert_equal value, cookies[name]

    delete_cookie(name)

    assert_nil cookies[name]
  end
end