require "test_helper"

class Admin::PicturesControllerTest < ActionController::TestCase
  test "should get index" do
    sign_in users(:admin)

    get :index

    assert_response :success
  assert_not_nil assigns(:pictures)

    assert_equal "Pictures", assigns(:title)
  end

  test "should ransack on picture tags" do
    sign_in users(:admin)

    picture_tag_id = PictureTag.all.first

    get :index, params: { q: { picture_tags_id_eq: picture_tag_id } }

    assert_response :success
  end
end
