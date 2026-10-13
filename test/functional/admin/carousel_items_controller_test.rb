require "test_helper"

class Admin::CarouselItemsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @carousel_item = CarouselItem.create!(title: "Spring season", tagline: "Now on sale",
                                          carousel_name: "Home", ordering: 1, is_active: true,
                                          image: Rack::Test::UploadedFile.new(Rails.root.join("test", "test.png"), "image/png"))
  end

  # Every label needs a simple_form.labels.defaults translation, or the page renders "Translation missing".
  test "should get index" do
    get :index

    assert_response :success
    assert_no_match(/Translation missing/, response.body)
  end

  test "should get new" do
    get :new

    assert_response :success
    assert_no_match(/Translation missing/, response.body)
  end

  # The carousel prints the tagline raw, so Markdown typed there (**bold**) would show literally.
  test "the tagline is a plain field, not the Markdown editor" do
    get :edit, params: { id: @carousel_item }

    assert_response :success
    assert_select "textarea#carousel_item_tagline"
    assert_select "[data-controller~=markdown-editor]", false,
                  "the tagline must not be authored as Markdown while it renders as plain text"
  end

  test "should update the tagline" do
    patch :update, params: { id: @carousel_item, carousel_item: { tagline: "Tickets from £8" } }

    assert_redirected_to admin_carousel_item_path(@carousel_item)
    assert_equal "Tickets from £8", @carousel_item.reload.tagline
  end
end
