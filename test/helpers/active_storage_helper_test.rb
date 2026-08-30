require "test_helper"

class ActiveStorageHelperTest < ActionView::TestCase
  test "default_image_blob" do
    blob = nil
    assert_no_difference("ActiveStorage::Attachment.count") do
      assert_difference("ActiveStorage::Blob.count") do
        blob = default_image_blob("bedlam.png")
      end
    end

    assert blob.filename = "active_storage_default/bedlam.png"

    assert_no_difference("ActiveStorage::Attachment.count") do
      assert_no_difference("ActiveStorage::Blob.count") do
        other_blob = default_image_blob("bedlam.png")

        assert_equal blob, other_blob
      end
    end
  end

  test "default_image_blob with invalid image filename" do
    assert_no_difference("ActiveStorage::Attachment.count") do
      assert_no_difference("ActiveStorage::Blob.count") do
        assert_raises ArgumentError do
          default_image_blob("pineapple.png")
        end
      end
    end
  end

  test "get file attached hint without file attached" do
    show = FactoryBot.create(:show, attach_image: false)

    assert_not show.image.attached?
    assert_nil get_file_attached_hint(show.image)
  end

  test "get file attached hint with default file attached" do
    news = FactoryBot.create(:news)
    news.image.attach(default_image_blob("bedlam.png"))

    assert news.image.attached?
    assert_nil get_file_attached_hint(news.image)
  end

  test "get file attached hint with file attached" do
    user = FactoryBot.create(:user)
    user.avatar.attach(io: File.open(Rails.root.join("test", "test.png")), filename: "test.png", content_type: "image/png")

    assert user.avatar.attached?
    assert get_file_attached_hint(user.avatar).starts_with? "Current file: "
    assert_match "test.png", get_file_attached_hint(user.avatar)
  end

  test "slideshow_variant" do
    assert slideshow_variant.is_a? Hash
    assert slideshow_variant[:resize_to_fill].is_a? Array
  end

  test "thumb_variant" do
    assert thumb_variant.is_a? Hash
    assert thumb_variant[:resize_to_fill].is_a? Array

    dimensions_array = thumb_variant[:resize_to_fill]

    scaler = 2

    scaled_dimensions_array = thumb_variant(scaler)[:resize_to_fill]

    assert_equal scaler * dimensions_array[0], scaled_dimensions_array[0]
    assert_equal scaler * dimensions_array[1], scaled_dimensions_array[1]
  end

  test "square_display_variant" do
    assert square_display_variant.is_a? Hash
    assert square_display_variant[:resize_to_fill].is_a? Array
  end

  test "large_display_variant" do
    assert large_display_variant.is_a? Hash
    assert large_display_variant[:resize_to_fill].is_a? Array
    assert_equal 1920, large_display_variant[:resize_to_fill][0]
    assert_equal 1200, large_display_variant[:resize_to_fill][1]
    assert_equal "webp", large_display_variant[:format]
    assert_equal(-1, large_display_variant.dig(:loader, :n))
  end

  test "square_thumb_variant" do
    assert square_thumb_variant.is_a? Hash

    dimensions_array = square_thumb_variant[:resize_to_fill]
    assert dimensions_array.is_a? Array

    assert_equal dimensions_array[0], dimensions_array[1]
    assert_equal dimensions_array[0], 150

    assert_equal square_thumb_variant(200)[:resize_to_fill].first, 200
  end

  test "all variants include webp conversion" do
    variants = [
      thumb_variant,
      thumb_variant(2),
      thumb_variant_public,
      medium_variant,
      slideshow_variant,
      square_thumb_variant,
      square_display_variant
    ]

    variants.each do |variant|
      assert_equal "webp", variant[:format], "#{variant.inspect} should be served as webp"
      assert_equal 80, variant.dig(:saver, :Q), "#{variant.inspect} should have Q: 80 saver"
      assert_equal(-1, variant.dig(:loader, :n), "#{variant.inspect} should have loader n: -1 for GIF support")
    end
  end

  # Variants declared convert: "webp" produced real WebP bytes but Rails derives
  # Variation#content_type from the :format key alone, so every variant on the live site was
  # served declaring image/png or image/jpeg. Browsers sniff and cope; og:image validators do not.
  VARIANTS = %i[thumb_variant medium_variant slideshow_variant square_thumb_variant
                square_display_variant large_display_variant].freeze

  test "every variant asks for webp with the key rails reads" do
    VARIANTS.each do |name|
      transformations = send(name)

      assert_equal "webp", transformations[:format], "#{name} does not set :format"
      assert_not transformations.key?(:convert), "#{name} still uses :convert, which rails ignores for content type"
    end
  end

  test "a variant is served with a content type that matches its bytes" do
    show = FactoryBot.create(:show)
    variant = show.fetch_image.variant(slideshow_variant).processed

    assert_equal "image/webp", variant.content_type

    bytes = variant.download
    assert_equal "RIFF", bytes[0, 4], "expected WebP container bytes"
    assert_equal "WEBP", bytes[8, 4], "expected WebP container bytes"
  end
end
