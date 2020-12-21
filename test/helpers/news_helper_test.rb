require 'test_helper'

class NewsHelperTest < ActionView::TestCase
  test 'generate preview' do
    wisdom = 'The world is like a pineapple. Very tough to get inside and it tries to eat you.'
    assert_equal wisdom, generate_preview(wisdom)

    more_wisdom = "#{wisdom}#{wisdom}\n#{wisdom}"
    assert_equal "#{wisdom}#{wisdom}", generate_preview(more_wisdom)

    wisdomest = "#{wisdom}</p>#{wisdom}</p>#{wisdom}"
    assert_equal "#{wisdom}</p>#{wisdom}", generate_preview(wisdomest)

    assert_equal '', generate_preview('')

    assert_equal '', generate_preview(nil)
  end
end
