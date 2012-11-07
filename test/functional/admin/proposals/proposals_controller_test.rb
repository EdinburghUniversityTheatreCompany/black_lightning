require 'test_helper'

class Admin::Proposals::ProposalsControllerTest < ActionController::TestCase
  setup do
    @admin_proposals_proposal = admin_proposals_proposals(:one)
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
      post :create, admin_proposals_proposal: { budget_admin: @admin_proposals_proposal.budget_admin, budget_contingency: @admin_proposals_proposal.budget_contingency, budget_costume: @admin_proposals_proposal.budget_costume, budget_eutc: @admin_proposals_proposal.budget_eutc, budget_other_sources: @admin_proposals_proposal.budget_other_sources, budget_props: @admin_proposals_proposal.budget_props, budget_publiciy: @admin_proposals_proposal.budget_publiciy, budget_royalties: @admin_proposals_proposal.budget_royalties, budget_set: @admin_proposals_proposal.budget_set, budget_tech: @admin_proposals_proposal.budget_tech, cast_female: @admin_proposals_proposal.cast_female, cast_male: @admin_proposals_proposal.cast_male, proposal_text: @admin_proposals_proposal.proposal_text, publicity_text: @admin_proposals_proposal.publicity_text, running_time: @admin_proposals_proposal.running_time, show_title: @admin_proposals_proposal.show_title }
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
    put :update, id: @admin_proposals_proposal, admin_proposals_proposal: { budget_admin: @admin_proposals_proposal.budget_admin, budget_contingency: @admin_proposals_proposal.budget_contingency, budget_costume: @admin_proposals_proposal.budget_costume, budget_eutc: @admin_proposals_proposal.budget_eutc, budget_other_sources: @admin_proposals_proposal.budget_other_sources, budget_props: @admin_proposals_proposal.budget_props, budget_publiciy: @admin_proposals_proposal.budget_publiciy, budget_royalties: @admin_proposals_proposal.budget_royalties, budget_set: @admin_proposals_proposal.budget_set, budget_tech: @admin_proposals_proposal.budget_tech, cast_female: @admin_proposals_proposal.cast_female, cast_male: @admin_proposals_proposal.cast_male, proposal_text: @admin_proposals_proposal.proposal_text, publicity_text: @admin_proposals_proposal.publicity_text, running_time: @admin_proposals_proposal.running_time, show_title: @admin_proposals_proposal.show_title }
    assert_redirected_to admin_proposals_proposal_path(assigns(:admin_proposals_proposal))
  end

  test "should destroy admin_proposals_proposal" do
    assert_difference('Admin::Proposals::Proposal.count', -1) do
      delete :destroy, id: @admin_proposals_proposal
    end

    assert_redirected_to admin_proposals_proposals_path
  end
end
