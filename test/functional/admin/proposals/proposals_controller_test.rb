require 'test_helper'

class Admin::Proposals::ProposalsControllerTest < ActionController::TestCase
  setup do
    @admin_proposals_proposal = admin_proposals_proposals(:one)

    @user = User.find_by_email('admin@bedlamtheatre.co.uk')
    @user.add_role :admin
    sign_in @user
  end

  test "should get index" do
    get :index, :call_id => 1
    assert_response :success
    assert_not_nil assigns(:proposals)
  end

  test "should get new" do
    get :new, :call_id => 1
    assert_response :success
  end

  test "should create admin_proposals_proposal" do
    assert_difference('Admin::Proposals::Proposal.count') do
      team_user = User.find_by_email('test@bedlamtheatre.co.uk')
      team_member = TeamMember.new()
      team_member.user = team_user
      team_member.position = 'Director'

      post :create, :call_id => 1, admin_proposals_proposal: { proposal_text: @admin_proposals_proposal.proposal_text, publicity_text: @admin_proposals_proposal.publicity_text, show_title: @admin_proposals_proposal.show_title, :team_members_attributes => { '0' => { 'position' => 'Director', 'user_id' => 1} } }
    end

    assert_redirected_to admin_proposals_call_proposal_path(1, assigns(:proposal))
  end

  test "should show admin_proposals_proposal" do
    get :show, :call_id => 1,  id: @admin_proposals_proposal
    assert_response :success
  end

  test "should get edit" do
    get :edit, :call_id => 1, id: @admin_proposals_proposal
    assert_response :success
  end

  test "should update admin_proposals_proposal" do
    team_user = User.find_by_email('test@bedlamtheatre.co.uk')

    put :update, :call_id => 1, id: @admin_proposals_proposal, admin_proposals_proposal: { proposal_text: @admin_proposals_proposal.proposal_text, publicity_text: @admin_proposals_proposal.publicity_text, show_title: @admin_proposals_proposal.show_title, :team_members_attributes => { '0' => { 'position' => 'Director', 'user_id' => 1} } }
    assert_redirected_to admin_proposals_call_proposal_path(1, assigns(:proposal))
  end

  test "should destroy admin_proposals_proposal" do
    call = @admin_proposals_proposal.call
    assert_difference('Admin::Proposals::Proposal.count', -1) do
      delete :destroy, :call_id => 1, id: @admin_proposals_proposal
    end

    assert_redirected_to admin_proposals_call_proposals_url(call)
  end
end
