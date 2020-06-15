require 'test_helper'

class PictureTest < ActionView::TestCase
  test 'missing image' do
    picture = FactoryBot.create(:picture, attach_image: false)
    assert_equal 'active_storage_default-missing.png', picture.fetch_image.filename.to_s
  end

  test 'thumb url' do
    picture = FactoryBot.create(:picture)
    assert_includes picture.thumb_url, 'test.png'
  end

  test 'display url' do
    picture = FactoryBot.create(:picture)
    assert_includes picture.display_url, 'test.png'
  end
end
