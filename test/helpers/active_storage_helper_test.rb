require 'test_helper'

class ActiveStorageHelperTest < ActionView::TestCase
  test 'default_image_blob' do 
    blob = nil
    assert_no_difference('ActiveStorage::Attachment.count') do
      assert_difference('ActiveStorage::Blob.count') do
        blob = default_image_blob('bedlam.png')
      end
    end

    assert blob.filename = 'active_storage_default/bedlam.png'

    assert_no_difference('ActiveStorage::Attachment.count') do
      assert_no_difference('ActiveStorage::Blob.count') do
        other_blob = default_image_blob('bedlam.png')

        assert_equal blob, other_blob
      end
    end
  end

  test 'default_image_blob with invalid image filename' do
    assert_raises ArgumentError do
      assert_no_difference('ActiveStorage::Attachment.count') do
        assert_no_difference('ActiveStorage::Blob.count') do
          default_image_blob('pineapple.png')
        end
      end
    end
  end

  test 'get file attached hint without file attached' do
    show = FactoryBot.create(:show, attach_image: false)

    assert_not show.image.attached?
    assert_nil get_file_attached_hint(show.image)
  end

  test 'get file attached hint with default file attached' do
    news = FactoryBot.create(:news)
    news.image.attach(default_image_blob('bedlam.png'))

    assert news.image.attached?
    assert_nil get_file_attached_hint(news.image)
  end

  test 'get file attached hint with file attached' do
    user = FactoryBot.create(:user)
    user.avatar.attach(io: File.open(Rails.root.join('test', 'test.png')), filename: 'test.png', content_type: 'image/png')
    
    assert user.avatar.attached?
    assert_equal 'The message next to the button is wrong. Current file: test.png', get_file_attached_hint(user.avatar)
  end

  test 'slideshow_variant' do
    assert slideshow_variant.is_a? Hash
    assert slideshow_variant.values.first.is_a? Array
  end

  test 'thumb_variant' do
    assert thumb_variant.is_a? Hash
    assert thumb_variant.values.first.is_a? Array
  end

  test 'square_display_variant' do
    assert square_display_variant.is_a? Hash
    assert square_display_variant.values.first.is_a? Array
  end

  test 'square_thumb_variant' do
    assert square_thumb_variant.is_a? Hash
    assert square_thumb_variant.values.first.is_a? Array
  end
end
