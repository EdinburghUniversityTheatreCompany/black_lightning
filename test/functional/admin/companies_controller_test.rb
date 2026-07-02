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

  test "editing a company marks it reviewed" do
    company = companies(:unreviewed_company)
    assert_not company.reviewed

    put :update, params: { id: company, company: { website: "https://example.com/added" } }

    assert company.reload.reviewed
  end

  test "creating a company via the admin marks it reviewed" do
    post :create, params: { company: { name: "Curated Company" } }

    assert assigns(:company).reviewed
  end

  test "should destroy company" do
    company = Company.create!(name: "Disposable Company")

    assert_difference("Company.count", -1) do
      delete :destroy, params: { id: company }
    end

    assert_redirected_to admin_companies_path
  end

  # A live-search fetch (from live_search_controller) requests the index as turbo_stream with q[...]
  # params, and gets the #index-results fragment for in-place filtering.
  test "index responds to a turbo_stream request with q params using the results fragment" do
    get :index, params: { q: { name_cont: @company.name } }, format: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/<turbo-stream[^>]*target="index-results"/, response.body)
  end

  # GenericController#destroy redirects to :index. Because a destroy is a Turbo form submission, the
  # browser follows the 302 with the same turbo_stream Accept header but no q params. Answering that
  # with the #index-results fragment would silently do nothing when the redirect lands somewhere
  # without that element (e.g. a show page) and the flash would never show — so serve the full page.
  test "index serves a full HTML page for a paramless turbo_stream request" do
    get :index, format: :turbo_stream

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_no_match(/<turbo-stream/, response.body)
  end
end
