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
end
