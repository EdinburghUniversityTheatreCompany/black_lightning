require 'test_helper'

class Admin::TechiesControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
    @techie = techies(:one)
  end

  test 'should get index' do
    get :index
    assert_response :success
  end

  test 'should get show' do
    get :show, params: { id: @techie.id }
    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  # Also tests if the association stuff works.
  test 'should create' do
    child = techies(:one)
    parent = techies(:two)

    attributes = {
      name: 'Brian Brocolli',
      parents_attributes: { '0' => { id: parent.id, '_destroy' => 'false' } },
      children_attributes: { '1' => { id: child.id, '_destroy' => 'false' } }
    }

    assert_difference 'Techie.count' do
      post :create, params: { techie: attributes }
    end

    assert child.parents.first, assigns(:techie)
    assert parent.children.first, assigns(:techie)

    assert_redirected_to admin_techie_path(assigns(:techie))
  end

  test 'should not create invalid' do
    attributes = { name: '' }

    assert_no_difference 'Techie.count' do
      post :create, params: { techie: attributes }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @techie.id }
    assert_response :success
  end

  test 'should update' do
    attributes = { name: 'Brian Brocolli' }

    patch :update, params: { id: @techie.id, techie: attributes }

    assert attributes[:name], assigns(:techie).name
    assert_redirected_to admin_techie_path(assigns(:techie))
  end

  test 'should not update invalid' do
    attributes = { name: nil }

    patch :update, params: { id: @techie.id, techie: attributes }

    assert_response :unprocessable_entity
  end

  test 'should destroy' do
    assert_difference 'Techie.count', -1 do
      delete :destroy, params: { id: techies(:two).id }
    end

    assert_redirected_to admin_techies_path
  end

  test 'should get tree' do
    get :tree
    assert_response :success
  end
end
