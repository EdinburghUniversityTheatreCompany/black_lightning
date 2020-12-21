require 'test_helper'

class Admin::AttachmentTagsControllerTest < ActionController::TestCase
  setup do
    @attachment_tag = attachment_tags(:rigplan)

    sign_in users(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:attachment_tags)
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create attachment_tag' do
    assert_difference('AttachmentTag.count') do
      params = FactoryBot.attributes_for(:attachment_tag)
      post :create, params: { attachment_tag: params }
    end

    assert_redirected_to admin_attachment_tag_path(assigns(:attachment_tag))
  end

  test 'should not create invalid attachment tag' do
    assert_no_difference('AttachmentTag.count') do
      # Duplicate name.
      params = FactoryBot.attributes_for(:attachment_tag, name: @attachment_tag.name)
      post :create, params: { attachment_tag: params }
    end

    assert_response :unprocessable_entity
  end

  test 'should show attachment tag' do
    get :show, params: { id: @attachment_tag }
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @attachment_tag }
    assert_response :success
  end

  test 'should update attachment_tag' do
    new_name = FactoryBot.generate(:random_string)

    put :update, params: { id: @attachment_tag, attachment_tag: { name: new_name } }

    assert_equal new_name, assigns(:attachment_tag).name

    assert_redirected_to admin_attachment_tag_path(assigns(:attachment_tag))
  end

  test 'should not update invalid attachment_tag' do
    put :update, params: { id: @attachment_tag, attachment_tag: { name: nil } }
    assert_response :unprocessable_entity
  end

  test 'should destroy attachment_tag' do
    assert_difference('AttachmentTag.count', -1) do
      delete :destroy, params: { id: @attachment_tag }
    end

    assert_redirected_to admin_attachment_tags_path
  end
end
