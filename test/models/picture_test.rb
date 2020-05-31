require 'test_helper'

class PictureTest < ActionView::TestCase
  test 'missing image urls' do
    picture = Picture.create

    assert_equal '/images/original/missing.png', picture.image_url

    assert_equal '/images/thumb/missing.png', picture.thumb_url
  end
end
