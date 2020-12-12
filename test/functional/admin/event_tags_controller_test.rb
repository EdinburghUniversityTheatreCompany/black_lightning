require 'test_helper'

class Admin::EventTagsControllerTest < ActionController::TestCase
  setup do
    @event_tag = event_tags(:mainterm)

    sign_in users(:admin)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:event_tags)
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create event_tag' do
    assert_difference('EventTag.count') do
      params = FactoryBot.attributes_for(:event_tag)
      post :create, params: { event_tag: params }
    end

    assert_redirected_to admin_event_tag_path(assigns(:event_tag))
  end

  test 'should not create invalid event tag' do
    assert_no_difference('EventTag.count') do
      # Duplicate name.
      params = FactoryBot.attributes_for(:event_tag, name: @event_tag.name)
      post :create, params: { event_tag: params }
    end

    assert_response :unprocessable_entity
  end

  test 'should show event tag' do
    get :show, params: { id: @event_tag }
    assert_response :success
  end

  test 'should get edit' do
    get :edit, params: { id: @event_tag }
    assert_response :success
  end

  test 'should update event_tag' do
    new_name = FactoryBot.generate(:random_string)

    put :update, params: { id: @event_tag, event_tag: { name: new_name } }

    assert_equal new_name, assigns(:event_tag).name

    assert_redirected_to admin_event_tag_path(assigns(:event_tag))
  end

  test 'should not update invalid event_tag' do
    put :update, params: { id: @event_tag, event_tag: { name: nil } }
    assert_response :unprocessable_entity
  end

  test 'should destroy event_tag' do
    assert_difference('EventTag.count', -1) do
      delete :destroy, params: { id: @event_tag }
    end

    assert_redirected_to admin_event_tags_path
  end
end
