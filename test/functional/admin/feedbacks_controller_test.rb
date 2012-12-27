require 'test_helper'

class Admin::FeedbacksControllerTest < ActionController::TestCase
  setup do
    @show = FactoryGirl.create(:show)

    sign_in FactoryGirl.create(:admin)
  end

  test "should get index" do
    FactoryGirl.create_list(:feedback, 10)

    get :index, :show_id => @show
    assert_response :success
    assert_not_nil assigns(:feedbacks)
  end

  test "should get new" do
    get :new, show_id: @show
    assert_response :success
  end

  test "should create admin_feedback" do
    @feedback = FactoryGirl.attributes_for(:feedback, show: @show)

    assert_difference('Admin::Feedback.count') do
      post :create, show_id: @show, admin_feedback: @feedback
    end

    assert_redirected_to admin_show_feedbacks_path(@show)
  end

  test "should get edit" do
    @feedback = FactoryGirl.create(:feedback, show: @show)

    get :edit, show_id: @show, id: @feedback
    assert_response :success
  end

  test "should update admin_feedback" do
    @feedback = FactoryGirl.create(:feedback, show: @show)
    @attrs = FactoryGirl.attributes_for(:feedback, show: @show)

    put :update, show_id: @show, id: @feedback, admin_feedback: @attrs
    assert_redirected_to admin_show_feedbacks_path(@show)
  end

  test "should destroy admin_feedback" do
    @feedback = FactoryGirl.create(:feedback, show: @show)

    assert_difference('Admin::Feedback.count', -1) do
      delete :destroy, show_id: @show, id: @feedback
    end

    assert_redirected_to admin_show_feedbacks_path(@show)
  end
end
