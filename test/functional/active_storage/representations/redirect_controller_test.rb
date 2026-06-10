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
end
