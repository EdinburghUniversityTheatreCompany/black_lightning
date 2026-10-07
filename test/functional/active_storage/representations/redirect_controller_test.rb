require "test_helper"

class ActiveStorage::Representations::RedirectControllerTest < ActionDispatch::IntegrationTest
  setup do
    @picture = FactoryBot.create(:picture)
  end

  test "redirects successfully for valid image blob" do
    attach_image(File.open(Rails.root.join("test", "test.png")))

    get_representation(@picture.image.variant(resize_to_fill: [ 100, 100 ]).variation.key)

    assert_response :redirect
  end

  test "returns 404 instead of 500 when variant processing fails" do
    # Bytes claiming to be a PNG, so vips raises a real processing error (Honeybadger #131577736).
    attach_image(StringIO.new("this is not a valid image"), "broken.png")

    get_representation(@picture.image.variant(resize_to_fill: [ 100, 100 ]).variation.key)

    assert_response :not_found
  end

  # A scanner replays the variation key without its signature (Honeybadger #133797247), and also
  # in the pre-Rails-5.2 Marshal encoding, a deserialisation attack's shape, which must be rejected
  # on its missing signature before anything unwraps it.
  test "returns 404 instead of 500 for an unsigned JSON or Marshal variation key" do
    attach_image(File.open(Rails.root.join("test", "test.png")))

    [
      { format: "png", resize_to_limit: [ 1920, 1080 ] }.to_json,
      Marshal.dump({ format: "png" })
    ].each do |payload|
      get_representation(Base64.urlsafe_encode64(payload, padding: false))

      assert_response :not_found
    end
  end

  private

  def attach_image(io, filename = "valid.png")
    @picture.image.attach(io:, filename:, content_type: "image/png")
  end

  def get_representation(variation_key)
    get rails_blob_representation_path(@picture.image.blob.signed_id, variation_key, @picture.image.filename)
  end
end
