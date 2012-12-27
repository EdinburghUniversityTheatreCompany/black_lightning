require 'test_helper'

class Admin::Proposals::ProposalsControllerTest < ActionController::TestCase
  setup do
    @call = FactoryGirl.create(:proposal_call, question_count: 5, open: true)

    sign_in FactoryGirl.create(:admin)
  end

  test "should get index" do
    FactoryGirl.create_list(:proposal, 10, call: @call)

    get :index, call_id: @call.id
    assert_response :success
    assert_not_nil assigns(:proposals)
  end

  test "shouldn't get new on closed call" do
    get :new, call_id: FactoryGirl.create(:proposal_call, open: false).id

    assert_redirected_to admin_proposals_calls_path
  end

  test "should get new" do
    get :new, call_id: @call.id

    assert_response :success
  end

  test "should create admin_proposals_proposal" do
    proposal = FactoryGirl.build(:proposal)

    # This mess is to force the inclusion of team_member attributes.
    attrs = proposal.attributes
    attrs.delete('id')
    attrs.delete('call_id')
    attrs.delete('created_at')
    attrs.delete('updated_at')

    team_members = {}
    i = 0
    proposal.team_members.each do |team_member|
      team_members[i] = team_member.attributes
      team_members[i].delete('id')
      team_members[i].delete('teamwork_id')
      team_members[i].delete('teamwork_type')
      team_members[i].delete('created_at')
      team_members[i].delete('updated_at')
      i += 1
    end

    attrs[:team_members_attributes] = team_members

    assert_difference('Admin::Proposals::Proposal.count') do
      post :create, call_id: @call.id, admin_proposals_proposal: attrs
    end

    assert_redirected_to admin_proposals_call_proposal_path(@call, assigns(:proposal))
  end

  test "should show admin_proposals_proposal" do
    @proposal = FactoryGirl.create(:proposal, call: @call)

    get :show, call_id: @call.id,  id: @proposal
    assert_response :success
  end

  test "should get edit" do
    @proposal = FactoryGirl.create(:proposal, call: @call)

    get :edit, call_id: @call.id, id: @proposal
    assert_response :success
  end

  test "should update admin_proposals_proposal" do
    @proposal = FactoryGirl.create(:proposal, call: @call)
    attrs = FactoryGirl.attributes_for(:proposal)

    put :update, call_id: @call.id, id: @proposal, admin_proposals_proposal: attrs
    assert_redirected_to admin_proposals_call_proposal_path(@call.id, assigns(:proposal))
  end

  test "should destroy admin_proposals_proposal" do
    @proposal = FactoryGirl.create(:proposal, call: @call)

    assert_difference('Admin::Proposals::Proposal.count', -1) do
      delete :destroy, call_id: @call.id, id: @proposal
    end

    assert_redirected_to admin_proposals_call_proposals_url(@call)
  end
end
