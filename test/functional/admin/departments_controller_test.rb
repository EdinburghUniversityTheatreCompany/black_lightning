require "test_helper"

class Admin::DepartmentsControllerTest < ActionController::TestCase
  setup do
    @user = users(:admin)
    sign_in @user
    @department = departments(:lighting)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:departments)
  end

  test "should get show" do
    get :show, params: { id: @department }
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @department }
    assert_response :success
  end

  test "should create department" do
    assert_difference("Department.count") do
      post :create, params: { department: { name: "Rigging", ordering: 12, match_terms: "rigger, rigging" } }
    end

    assert_redirected_to admin_department_path(assigns(:department))
  end

  test "should not create invalid department" do
    assert_no_difference("Department.count") do
      post :create, params: { department: { name: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "should update department" do
    put :update, params: { id: @department, department: { match_terms: "light, lx, lanterns" } }

    assert_equal "light, lx, lanterns", @department.reload.match_terms
    assert_redirected_to admin_department_path(@department)
  end

  test "should destroy department" do
    department = Department.create!(name: "Disposable Department")

    assert_difference("Department.count", -1) do
      delete :destroy, params: { id: department }
    end

    assert_redirected_to admin_departments_path
  end
end
