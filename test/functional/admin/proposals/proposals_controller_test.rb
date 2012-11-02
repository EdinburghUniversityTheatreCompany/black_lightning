require 'test_helper'

class Admin::Proposals::ProposalsControllerTest < ActionController::TestCase
  setup do
    @admin_proposals_proposal = admin_proposals_proposals(:one)
    
    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_proposals_proposals)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create admin_proposals_proposal" do
    assert_difference('Admin::Proposals::Proposal.count') do
      post :create, admin_proposals_proposal: { proposal_text: @admin_proposals_proposal.proposal_text, publicity_text: @admin_proposals_proposal.publicity_text, show_title: @admin_proposals_proposal.show_title }
    end

    assert_redirected_to admin_proposals_proposal_path(assigns(:admin_proposals_proposal))
  end

  test "should show admin_proposals_proposal" do
    get :show, id: @admin_proposals_proposal
    assert_response :success
  end

  test "should get edit" do
    get :edit, id: @admin_proposals_proposal
    assert_response :success
  end

  test "should update admin_proposals_proposal" do
    put :update, id: @admin_proposals_proposal, admin_proposals_proposal: { proposal_text: @admin_proposals_proposal.proposal_text, publicity_text: @admin_proposals_proposal.publicity_text, show_title: @admin_proposals_proposal.show_title }
    assert_redirected_to admin_proposals_proposal_path(assigns(:admin_proposals_proposal))
  end

  test "should destroy admin_proposals_proposal" do
    assert_difference('Admin::Proposals::Proposal.count', -1) do
      delete :destroy, id: @admin_proposals_proposal
    end

    assert_redirected_to admin_proposals_proposals_path
  end
end
