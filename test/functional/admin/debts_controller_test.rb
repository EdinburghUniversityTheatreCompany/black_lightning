require "test_helper"

class Admin::DebtsControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin
    @member = FactoryBot.create(:member)
  end

  test "should get index" do
    get :index
    assert_response :success

    assert_equal User.with_role(:member).all.ids.sort, assigns(:users).ids.sort, "Not all users with the members role are included in the index"
  end

  test "should get index with only in debt" do
    FactoryBot.create(:overdue_staffing_debt, user: @member)

    get :index, params: { show_in_debt_only: 1 }
    assert_response :success

    assert_includes assigns(:users).to_a, @member, "The user with debt is not included in the index when show_in_debt_only is true"
    assert_not_includes assigns(:users).to_a, @admin, "The user without debt is included in the index when show_in_debt_only is true"
  end

  test "should get show" do
    get :show, params: { id: @member.id }
    assert_response :success
  end

  test "should not get show for other user" do
    sign_out @admin
    sign_in @member

    get :show, params: { id: @admin.id }

    assert_response 403
  end

  # Live-search fetch: turbo_stream + q[...] params → the #index-results fragment.
  test "index responds to a turbo_stream request with q params using the results fragment" do
    get :index, params: { q: { last_name_cont: @member.last_name } }, format: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/<turbo-stream[^>]*target="index-results"/, response.body)
  end

  # A paramless turbo_stream request (e.g. a Turbo form-submission redirect) must render the full
  # HTML page, not the fragment. See ApplicationController#render_index_stream_or_full.
  test "index serves a full HTML page for a paramless turbo_stream request" do
    get :index, format: :turbo_stream

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_no_match(/<turbo-stream/, response.body)
  end
end
