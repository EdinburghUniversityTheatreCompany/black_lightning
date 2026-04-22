require "test_helper"

class Admin::Proposals::CallsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @call = FactoryBot.create :proposal_call
  end

  test "should get index" do
    FactoryBot.create_list(:proposal_call, 3)

    get :index
    assert_response :success
    assert_not_nil assigns(:calls)
  end

  test "index shows awaiting_approval and approved proposals with actions for approver" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))

    awaiting = FactoryBot.create(:proposal, call: @call, status: :awaiting_approval)
    approved = FactoryBot.create(:proposal, call: @call, status: :approved)
    FactoryBot.create(:proposal, call: @call, status: :rejected)
    FactoryBot.create(:proposal, call: @call, status: :successful)

    get :index

    assert_response :success
    assert_includes assigns(:awaiting_approval), awaiting
    assert_includes assigns(:approved), approved
    assert_equal 1, assigns(:awaiting_approval).size
    assert_equal 1, assigns(:approved).size

    assert_match approve_admin_proposals_proposal_path(awaiting), response.body
    assert_match reject_admin_proposals_proposal_path(awaiting), response.body
    assert_match mark_successful_admin_proposals_proposal_path(approved), response.body
    assert_match mark_unsuccessful_admin_proposals_proposal_path(approved), response.body
  end

  test "index is viewable without approve permission but hides action buttons" do
    sign_out users(:admin)
    sign_in users(:committee)

    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))

    awaiting = FactoryBot.create(:proposal, call: @call, status: :awaiting_approval)
    approved = FactoryBot.create(:proposal, call: @call, status: :approved)

    get :index

    assert_response :success
    assert_includes assigns(:awaiting_approval), awaiting
    assert_includes assigns(:approved), approved

    assert_no_match(/#{Regexp.escape approve_admin_proposals_proposal_path(awaiting)}/, response.body)
    assert_no_match(/#{Regexp.escape reject_admin_proposals_proposal_path(awaiting)}/, response.body)
    assert_no_match(/#{Regexp.escape mark_successful_admin_proposals_proposal_path(approved)}/, response.body)
    assert_no_match(/#{Regexp.escape mark_unsuccessful_admin_proposals_proposal_path(approved)}/, response.body)
  end

  test "index hides proposals a member cannot read" do
    sign_out users(:admin)
    sign_in users(:member)

    hidden_awaiting = FactoryBot.create(:proposal, call: @call, status: :awaiting_approval)
    visible_approved = FactoryBot.create(:proposal, call: @call, status: :approved)

    get :index

    assert_response :success
    assert_not_includes assigns(:awaiting_approval), hidden_awaiting,
      "A member not on the proposal should not see awaiting_approval proposals before the submission deadline."
    assert_includes assigns(:approved), visible_approved,
      "Approved proposals should be visible to any logged-in user."
  end

  test "index surfaces open calls with no proposals and renders new proposal button for creators" do
    sign_out users(:admin)
    sign_in users(:member)

    get :index

    assert_response :success
    assert_includes assigns(:open_calls), @call
    assert_match @call.name, response.body
    assert_match new_admin_proposals_proposal_path(call_id: @call.id), response.body
  end

  test "index hides new proposal button from users who cannot create proposals" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
    FactoryBot.create(:proposal, call: @call, status: :awaiting_approval)

    sign_out users(:admin)
    sign_in users(:member)

    get :index

    assert_response :success
    assert_no_match(/#{Regexp.escape new_admin_proposals_proposal_path(call_id: @call.id)}/, response.body)
  end

  test "should show call" do
    get :show, params: { id: @call }
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create call" do
    attributes = FactoryBot.attributes_for(:proposal_call)

    assert_difference("Admin::Proposals::Call.count") do
      post :create, params: { admin_proposals_call: attributes }
    end

    assert_redirected_to admin_proposals_call_path(assigns(:call))
  end

  test "should not create invalid call" do
    attributes = FactoryBot.attributes_for(:proposal_call, editing_deadline: nil)

    assert_no_difference("Admin::Proposals::Call.count") do
      post :create, params: { admin_proposals_call: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit" do
    get :edit, params: { id: @call }

    assert_response :success
  end

  test "should update call" do
    attributes = FactoryBot.attributes_for(:proposal_call, question_count: 3)

    put :update, params: { id: @call, admin_proposals_call: attributes }

    assert_redirected_to admin_proposals_call_path(assigns(:call))
  end

  test "should not update invalid call" do
    attributes = FactoryBot.attributes_for(:proposal_call, name: nil, question_count: 3)

    put :update, params: { id: @call, admin_proposals_call: attributes }

    assert_response :unprocessable_entity
  end

  test "should destroy call" do
    @call.proposals.clear

    assert_difference("Admin::Proposals::Call.count", -1) do
      delete :destroy, params: { id: @call }
    end

    assert_redirected_to admin_proposals_calls_path
  end

  test "should archive call" do
    @call.update_attribute(:editing_deadline, DateTime.current.advance(days: -1))
    @call.update_attribute(:archived, false)

    assert_no_difference("Admin::Proposals::Call.count") do
      put :archive, params: { id: @call }
    end

    assert assigns(:call).archived

    assert_redirected_to admin_proposals_calls_path
  end

  test "should not archive call with an editing deadline in the future." do
    @call.update_attribute(:editing_deadline, DateTime.current.advance(days: 1))
    @call.update_attribute(:archived, false)

    assert_no_difference("Admin::Proposals::Call.count") do
      put :archive, params: { id: @call }
    end

    assert_not assigns(:call).archived

    assert_redirected_to admin_proposals_calls_path
  end
end
