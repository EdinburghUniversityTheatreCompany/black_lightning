require 'test_helper'

class Admin::FeedbacksControllerTest < ActionController::TestCase
  setup do
    @admin_feedback = admin_feedbacks(:one)

    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index, :show_id => "accidental-death-of-an-anarchist"
    assert_response :success
    assert_not_nil assigns(:feedbacks)
  end

  test "should get new" do
    get :new, :show_id => "accidental-death-of-an-anarchist"
    assert_response :success
  end

  test "should create admin_feedback" do
    assert_difference('Admin::Feedback.count') do
      post :create, :show_id => "accidental-death-of-an-anarchist", admin_feedback: { body: @admin_feedback.body, show_id: @admin_feedback.show_id }
    end

    assert_redirected_to admin_show_feedbacks_path("accidental-death-of-an-anarchist")
  end

  test "should get edit" do
    get :edit, :show_id => "accidental-death-of-an-anarchist", id: @admin_feedback
    assert_response :success
  end

  test "should update admin_feedback" do
    put :update, :show_id => "accidental-death-of-an-anarchist", id: @admin_feedback, admin_feedback: { body: @admin_feedback.body, show_id: @admin_feedback.show_id }
    assert_redirected_to admin_show_feedbacks_path("accidental-death-of-an-anarchist")
  end

  test "should destroy admin_feedback" do
    assert_difference('Admin::Feedback.count', -1) do
      delete :destroy, :show_id => "accidental-death-of-an-anarchist", id: @admin_feedback
    end

    assert_redirected_to admin_show_feedbacks_path("accidental-death-of-an-anarchist")
  end
end
