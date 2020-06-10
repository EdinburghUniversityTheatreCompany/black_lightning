require 'test_helper'

class ActiveStorageHelperTest < ActionView::TestCase
  test 'slideshow_variant' do
    assert slideshow_variant.is_a? Hash
  end

  test 'thumb_variant' do
    slideshow_variant.is_a? Hash
  end
end
