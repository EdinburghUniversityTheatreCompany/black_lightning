require 'test_helper'

class Admin::PictureTagsControllerTest < ActionController::TestCase
  setup do
    @picture_tag = picture_tags(:performance)

    sign_in users(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:picture_tags)
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create picture_tag' do
    assert_difference('PictureTag.count') do
      params = FactoryBot.attributes_for(:picture_tag)
      post :create, params: { picture_tag: params }
    end

    assert_redirected_to admin_picture_tag_path(assigns(:picture_tag))
  end

  test 'should not create invalid picture tag' do
    assert_no_difference('PictureTag.count') do
      # Duplicate name.
      params = FactoryBot.attributes_for(:picture_tag, name: @picture_tag.name)
      post :create, params: { picture_tag: params }
    end

    assert_response :unprocessable_entity
  end

  test 'should show picture tag' do
    get :show, params: { id: @picture_tag }
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @picture_tag }
    assert_response :success
  end

  test 'should update picture_tag' do
    new_name = FactoryBot.generate(:random_string)

    put :update, params: { id: @picture_tag, picture_tag: { name: new_name } }

    assert_equal new_name, assigns(:picture_tag).name

    assert_redirected_to admin_picture_tag_path(assigns(:picture_tag))
  end

  test 'should not update invalid picture_tag' do
    put :update, params: { id: @picture_tag, picture_tag: { name: nil } }
    assert_response :unprocessable_entity
  end

  test 'should destroy picture_tag' do
    assert_difference('PictureTag.count', -1) do
      delete :destroy, params: { id: @picture_tag }
    end

    assert_redirected_to admin_picture_tags_path
  end
end
