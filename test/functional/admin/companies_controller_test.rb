require "test_helper"

class Admin::CompaniesControllerTest < ActionController::TestCase
  setup do
    @user = users(:admin)
    sign_in @user
    @company = companies(:gutter_theatre)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:companies)
  end

  test "should get show" do
    get :show, params: { id: @company }
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should get edit" do
    get :edit, params: { id: @company }
    assert_response :success
  end

  test "should create company" do
    assert_difference("Company.count") do
      post :create, params: { company: { name: "Brand New Company", internal: true, website: "https://example.com" } }
    end

    assert_equal "brand-new-company", assigns(:company).slug
    assert_redirected_to admin_company_path(assigns(:company))
  end

  test "should not create invalid company" do
    assert_no_difference("Company.count") do
      post :create, params: { company: { name: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "should update company" do
    put :update, params: { id: @company, company: { name: "Renamed Theatre" } }

    assert_equal "Renamed Theatre", @company.reload.name
    assert_redirected_to admin_company_path(@company)
  end

  test "should destroy company" do
    company = Company.create!(name: "Disposable Company")

    assert_difference("Company.count", -1) do
      delete :destroy, params: { id: company }
    end

    assert_redirected_to admin_companies_path
  end
end
