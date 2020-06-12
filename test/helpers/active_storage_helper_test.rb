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

  test 'slideshow_variant' do
    assert slideshow_variant.is_a? Hash
    assert slideshow_variant.values.first.is_a? Array
  end

  test 'thumb_variant' do
    assert thumb_variant.is_a? Hash
    assert thumb_variant.values.first.is_a? Array
  end
end
