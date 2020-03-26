require 'test_helper'

class Admin::Proposals::ProposalsControllerTest < ActionController::TestCase
  setup do
    @call = FactoryBot.create(:proposal_call, question_count: 5, open: true)

    sign_in FactoryBot.create(:admin)
  end

  test 'should get index' do
    FactoryBot.create_list(:proposal, 10, call: @call)

    get :index, params: {call_id: @call.id}
    assert_response :success
    assert_not_nil assigns(:proposals)
  end

  test "shouldn't get new on closed call" do
    get :new, call_id: FactoryBot.create(:proposal_call, open: false).id

    assert_redirected_to admin_proposals_calls_path
  end

  test 'should get new' do
    get :new, params: {call_id: @call.id}
    assert_response :success
  end

  test 'should create admin_proposals_proposal' do
    proposal = FactoryBot.build(:proposal)

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
      post :create, params: {call_id: @call.id, admin_proposals_proposal: attrs}
    end

    assert_redirected_to admin_proposals_call_proposal_path(@call, assigns(:proposal))
  end

  test 'should show admin_proposals_proposal' do
    @proposal = FactoryBot.create(:proposal, call: @call)

    get :show, call_id: @call.id,  id: @proposal
    assert_response :success
  end

  test 'should get edit' do
    @proposal = FactoryBot.create(:proposal, call: @call)

    get :edit, params: {call_id: @call.id, id: @proposal}
    assert_response :success
  end

  test 'should update admin_proposals_proposal' do
    @proposal = FactoryBot.create(:proposal, call: @call)
    attrs = FactoryBot.attributes_for(:proposal)

    put :update, params: {call_id: @call.id, id: @proposal, admin_proposals_proposal: attrs}
    assert_redirected_to admin_proposals_call_proposal_path(@call.id, assigns(:proposal))
  end

  test 'should destroy admin_proposals_proposal' do
    @proposal = FactoryBot.create(:proposal, call: @call)

    assert_difference('Admin::Proposals::Proposal.count', -1) do
      delete :destroy, params: {call_id: @call.id, id: @proposal}
    end

    assert_redirected_to admin_proposals_call_proposals_url(@call)
  end

  test 'members should not view other proposals before the deadline' do
    @call = FactoryBot.create(:proposal_call, proposal_count: 5, open: true, deadline: 5.days.from_now)
    @proposal = FactoryBot.create(:proposal, call: @call)
    member = FactoryBot.create(:member)

    sign_in member

    get :index, params: {call_id: @call.id}
    proposals = assigns(:proposals)
    assert_response :success
    assert_equal proposals.count, 0

    get :show, call_id: @call.id,  id: @proposal
    assert_redirected_to static_path('access_denied')
  end

  test 'members should view their own proposals before the deadline' do
    @call = FactoryBot.create(:proposal_call, proposal_count: 5, open: true, deadline: 5.days.from_now)
    @proposal = FactoryBot.create(:proposal, call: @call)
    member = FactoryBot.create(:member)

    sign_in member

    @proposal.team_members << FactoryBot.create(:team_member, user: member)
    @proposal.save

    get :index, params: {call_id: @call.id}
    proposals = assigns(:proposals)
    assert_response :success
    assert_equal proposals.count, 1

    get :show, call_id: @call.id,  id: @proposal
    assert_response :success
  end

  test 'committee should not view other proposals before the deadline' do
    @call = FactoryBot.create(:proposal_call, proposal_count: 5, open: true, deadline: 5.days.from_now)
    @proposal = FactoryBot.create(:proposal, call: @call)
    member = FactoryBot.create(:committee)

    sign_in member

    get :index, params: {call_id: @call.id}
    proposals = assigns(:proposals)
    assert_response :success
    assert_equal proposals.count, 0

    get :show, params: {call_id: @call.id,  id: @proposal}
    assert_redirected_to static_path('access_denied')
  end

  test 'committee should view their own proposals before the deadline' do
    @call = FactoryBot.create(:proposal_call, proposal_count: 5, open: true, deadline: 5.days.from_now)
    @proposal = FactoryBot.create(:proposal, call: @call)
    member = FactoryBot.create(:committee)

    sign_in member

    @proposal.team_members << FactoryBot.create(:team_member, user: member)
    @proposal.save

    get :index, params: {call_id: @call.id}
    proposals = assigns(:proposals)
    assert_response :success
    assert_equal proposals.count, 1

    get :show, call_id: @call.id,  id: @proposal
    assert_response :success
  end

  test 'committee should see all proposals after the deadline' do
    @call = FactoryBot.create(:proposal_call, proposal_count: 5, open: true, deadline: 1.days.ago)
    @proposal = FactoryBot.create(:proposal, call: @call)
    member = FactoryBot.create(:committee)

    sign_in member

    get :index, params: {call_id: @call.id}
    proposals = assigns(:proposals)
    assert_response :success
    assert_equal proposals.count, 6

    get :show, call_id: @call.id,  id: @proposal
    assert_response :success
  end

  test 'members should see only approved proposals after the deadline' do
    @call = FactoryBot.create(:proposal_call, open: true, deadline: 1.days.ago)
    @approved = FactoryBot.create(:proposal, call: @call, approved: true)
    @rejected = FactoryBot.create(:proposal, call: @call, approved: false)
    @waiting = FactoryBot.create(:proposal, call: @call, approved: nil)

    member = FactoryBot.create(:member)
    sign_in member

    get :index, call_id: @call.id
    proposals = assigns(:proposals)
    assert_response :success

    assert_equal 1, proposals.all.count

    get :show, call_id: @call.id,  id: @approved
    assert_response :success

    get :show, call_id: @call.id,  id: @rejected
    assert_redirected_to static_path('access_denied')

    get :show, call_id: @call.id,  id: @waiting
    assert_redirected_to static_path('access_denied')
  end
end
