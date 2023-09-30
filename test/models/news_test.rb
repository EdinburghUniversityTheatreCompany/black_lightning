# == Schema Information
#
# Table name: news
#
# *id*::                 <tt>integer, not null, primary key</tt>
# *title*::              <tt>string(255)</tt>
# *body*::               <tt>text(65535)</tt>
# *slug*::               <tt>string(255)</tt>
# *publish_date*::       <tt>datetime</tt>
# *show_public*::        <tt>boolean</tt>
# *created_at*::         <tt>datetime, not null</tt>
# *updated_at*::         <tt>datetime, not null</tt>
# *image_file_name*::    <tt>string(255)</tt>
# *image_content_type*:: <tt>string(255)</tt>
# *image_file_size*::    <tt>integer</tt>
# *image_updated_at*::   <tt>datetime</tt>
# *author_id*::          <tt>integer</tt>
#--
# == Schema Information End
#++
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
