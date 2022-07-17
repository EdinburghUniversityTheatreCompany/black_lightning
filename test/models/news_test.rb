require 'test_helper'

class NewsTest < ActionView::TestCase
  test 'preview' do
    news = News.new

    wisdom = 'The world is like a pineapple. Very tough to get inside and it tries to eat you.'
    news.body = wisdom
    assert_equal wisdom, news.preview

    news.body = "#{wisdom}#{wisdom}\n#{wisdom}"
    assert_equal "#{wisdom}#{wisdom}", news.preview

    news.body = "#{wisdom}</p>#{wisdom}</p>#{wisdom}"
    assert_equal "#{wisdom}</p>#{wisdom}", news.preview

    news.body = ''
    assert_equal '', news.preview

    news.body = nil
    assert_equal '', news.preview
  end
end
