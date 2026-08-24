require "test_helper"

class ActiveStorage::Representations::RedirectControllerTest < ActionDispatch::IntegrationTest
  setup do
    @picture = FactoryBot.create(:picture)
  end

  test "redirects successfully for valid image blob" do
    # Attach a valid image
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
    # Attach bytes that are not a valid image but claim to be a PNG, so the
    # image backend (vips) raises a real processing error when it tries to
    # transform the variant. Reproduces Honeybadger #131577736, where the
    # controller's rescue clause referenced an undefined constant and turned an
    # image-backend failure into a 500 instead of the intended 404.
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
    # A vulnerability scanner strips the signature off the variation key and
    # replays it against a validly signed blob id, probing whether the app will
    # run an unsigned set of image transformations. Rails refuses (that is the
    # point of the signature), but the refusal must read as "no such variant",
    # not as an application crash. Reproduces Honeybadger #133797247.
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
    # The same scanner also replays the pre-Rails-5.2 Marshal encoding, which is
    # the shape a deserialisation attack would take. It must never be unwrapped:
    # a 404 here proves the payload was rejected on its missing signature,
    # before anything looked at what it contained.
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
