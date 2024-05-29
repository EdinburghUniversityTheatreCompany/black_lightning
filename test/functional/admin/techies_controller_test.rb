require 'test_helper'

class Admin::TechiesControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin

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


  test 'should get mass new' do
    get :mass_new
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

  test 'should mass create' do
    relationships_data = "parent_1, parent_2 > child_1, child_2, child_3\nFinbar the Viking > child_4, child_5"

    # Should create all parents and children except for Finbar, who already exists.
    assert_difference('Techie.count', 7) do
      post :mass_create, params: { techie: { relationships_data: relationships_data } }
    end

    parent_1 = Techie.find_by(name: 'parent_1')
    parent_2 = Techie.find_by(name: 'parent_2')
    parent_3 = Techie.find_by(name: 'Finbar the Viking')
    child_1 = Techie.find_by(name: 'child_1')
    child_2 = Techie.find_by(name: 'child_2')
    child_3 = Techie.find_by(name: 'child_3')
    child_4 = Techie.find_by(name: 'child_4')
    child_5 = Techie.find_by(name: 'child_5')

    assert_not_nil parent_1
    assert_not_nil parent_2
    assert_not_nil parent_3
    assert_not_nil child_1
    assert_not_nil child_2
    assert_not_nil child_3
    assert_not_nil child_4
    assert_not_nil child_5

    assert_includes parent_1.children, child_1
    assert_includes parent_1.children, child_2
    assert_includes parent_1.children, child_3
    assert_includes parent_2.children, child_1
    assert_includes parent_2.children, child_2
    assert_includes parent_2.children, child_3
    assert_includes parent_3.children, child_4
    assert_includes parent_3.children, child_5
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

  test 'should get tree data' do
    get :tree_data

    assert_response :success

    json = JSON.parse(response.body)

    assert json.is_a? Hash
    assert json.key? 'nodes'
    assert json.key? 'edges'
  end

  test 'should get bush' do
    get :bush
    assert_response :success
  end

  test 'should get bush with one base techie' do
    get :bush, params: { q: { id_eq: Techie.all.last } }
    assert_response :success
  end

  test 'should get tree if you have index permission' do
    sign_out @admin
    sign_in users(:committee)

    get :tree
    assert_response :success
  end
end
