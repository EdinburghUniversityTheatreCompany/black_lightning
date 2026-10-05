require "test_helper"

class ActiveStorage::Representations::RedirectControllerTest < ActionDispatch::IntegrationTest
  setup do
    @picture = FactoryBot.create(:picture)
  end

  test "redirects successfully for valid image blob" do
    @picture.image.attach(
      io: File.open(Rails.root.join("test", "test.png")),
      filename: "valid.png",
      content_type: "image/png"
    )

    variant = @picture.image.variant(resize_to_fill: [ 100, 100 ])
    representation_url = rails_blob_representation_path(
      @picture.image.blob.signed_id,
      variant.variation.key,
      @picture.image.filename
    )

    get representation_url

    assert_response :redirect
  end

  test "returns 404 instead of 500 when variant processing fails" do
    # Bytes claiming to be a PNG, so vips raises a real processing error (Honeybadger #131577736).
    @picture.image.attach(
      io: StringIO.new("this is not a valid image"),
      filename: "broken.png",
      content_type: "image/png"
    )

    variant = @picture.image.variant(resize_to_fill: [ 100, 100 ])
    representation_url = rails_blob_representation_path(
      @picture.image.blob.signed_id,
      variant.variation.key,
      @picture.image.filename
    )

    get representation_url

    assert_response :not_found
  end

  test "returns 404 instead of 500 for an unsigned variation key" do
    # A scanner replaying the variation key without its signature (Honeybadger #133797247).
    @picture.image.attach(
      io: File.open(Rails.root.join("test", "test.png")),
      filename: "valid.png",
      content_type: "image/png"
    )

    forged_key = Base64.urlsafe_encode64(
      { format: "png", resize_to_limit: [ 1920, 1080 ] }.to_json, padding: false
    )

    get rails_blob_representation_path(
      @picture.image.blob.signed_id, forged_key, @picture.image.filename
    )

    assert_response :not_found
  end

  test "returns 404 for a Marshal-encoded variation key" do
    # The pre-Rails-5.2 Marshal encoding, a deserialisation attack's shape: it must be rejected on
    # its missing signature before anything unwraps it.
    @picture.image.attach(
      io: File.open(Rails.root.join("test", "test.png")),
      filename: "valid.png",
      content_type: "image/png"
    )

    marshal_key = Base64.urlsafe_encode64(Marshal.dump({ format: "png" }), padding: false)

    get rails_blob_representation_path(
      @picture.image.blob.signed_id, marshal_key, @picture.image.filename
    )

    assert_response :not_found
  end
end
