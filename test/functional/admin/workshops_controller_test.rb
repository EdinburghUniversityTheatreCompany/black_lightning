require "test_helper"

class Admin::WorkshopsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test "should get index" do
    FactoryBot.create_list(:workshop, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:events)
  end

  test "should get show" do
    @workshop = FactoryBot.create(:workshop)

    get :show, params: { id: @workshop }
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create workshop" do
    attributes = FactoryBot.attributes_for(:workshop)

    assert_difference("Workshop.count") do
      post :create, params: { workshop: attributes }
    end

    assert_redirected_to admin_workshop_path(assigns(:workshop))
  end

  test "should not create invalid workshop" do
    attributes = FactoryBot.attributes_for(:workshop, publicity_text: nil)

    assert_no_difference("Workshop.count") do
      post :create, params: { workshop: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit" do
    @workshop = FactoryBot.create(:workshop)

    get :edit, params: { id: @workshop }
    assert_response :success
  end

  test "should update workshop" do
    @workshop = FactoryBot.create(:workshop)
    attributes = FactoryBot.attributes_for(:workshop)

    put :update, params: { id: @workshop, workshop: attributes }

    assert_equal attributes[:name], assigns(:workshop).name

    assert_redirected_to admin_workshop_path(assigns(:workshop))
  end

  test "should not update invalid workshop" do
    @workshop = FactoryBot.create(:workshop)
    attributes = FactoryBot.attributes_for(:workshop, publicity_text: nil)

    put :update, params: { id: @workshop, workshop: attributes }

    assert_response :unprocessable_entity
  end

  test "should destroy workshop" do
    @workshop = FactoryBot.create(:workshop, team_member_count: 0, picture_count: 0, review_count: 0)

    assert_difference("Workshop.count", -1) do
      delete :destroy, params: { id: @workshop }
    end

    assert_redirected_to admin_workshops_path
  end
end
