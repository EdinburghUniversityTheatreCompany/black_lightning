require "test_helper"

class Admin::Proposals::ProposalsControllerTest < ActionController::TestCase
  include NameHelper

  setup do
    @call = FactoryBot.create(:proposal_call, question_count: 5, submission_deadline: DateTime.current.advance(days: 5))

    @admin = users(:admin)
    sign_in @admin
  end

  test "should get index" do
    FactoryBot.create_list(:proposal, 10, call: @call)

    get :index, params: { call_id: @call.id }
    assert_response :success
    assert_not_nil assigns(:proposals)
  end

  test "should show proposal" do
    sign_out @admin
    proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
    proposal.users.first.add_role :admin
    sign_in proposal.users.first

    get :show, params: { id: proposal }
    assert_response :success
  end

  test "someone on the proposal can see debt status" do
    sign_out @admin

    proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
    user = proposal.users.first
    user.add_role(:member)
    debtor = proposal.users.last

    assert_not_nil user
    assert_not_equal user, debtor, "The debtor is the same as the current user. This means the test will not be accurate. Did you add more than 1 person to the proposal?"

    FactoryBot.create(:maintenance_debt, user: debtor, due_by: Date.current.advance(days: -1))

    sign_in user

    get :show, params: { id: proposal }

    assert_response :success

    assert_match "text-danger", response.body
    assert_match "In maintenance debt", response.body

    assert_match 'text-danger">Has Debtors</span>', response.body, "The Has Debtors label is absent. Are you sure the label generation did not change? Are you sure one of the users is actually in debt (most likely because there is a maintenance debt label)?"
  end

  test "should get new" do
    # Do it with a member so we can also check the permissions.
    sign_out @admin

    sign_in users(:member)

    get :new, params: { call_id: @call.id }
    assert_response :success
  end

  test "should not get new after the submission deadline" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(hours: -1))
    get :new, params: { call_id: @call.id }

    assert_includes flash[:error].first, "The submission deadline for #{@call.name} has been passed"
    assert_redirected_to admin_proposals_call_proposals_path(@call)
  end

  test "should create proposal" do
    # Do it with a member so we can also check the permissions.
    sign_out @admin

    sign_in users(:member)
    # This mess is to force the inclusion of team_member attributes.
    # You cannot just use attributes_for, and team_work does not actually get an user linked when using build.
    proposal = FactoryBot.build(:proposal)

    attributes = FactoryBot.attributes_for(:proposal, call_id: @call.id)
    attributes[:status] = nil # The status needs to be assigned in the create. If this is not done, the proposal will not be saved, and the test will fail.

    team_members_count = 4
    attributes[:team_members_attributes] = generate_team_member_attributes(team_members_count)

    assert_difference("Admin::Proposals::Proposal.count") do
      post :create, params: { call_id: @call.id, admin_proposals_proposal: attributes }
    end

    assert_enqueued_emails team_members_count

    assert_redirected_to admin_proposals_proposal_path(assigns(:proposal))
  end

  test "should not create invalid proposal" do
    attributes = FactoryBot.attributes_for(:proposal, show_title: nil, call_id: @call.id)

    assert_no_difference("Admin::Proposals::Proposal.count") do
      post :create, params: { admin_proposals_proposal: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should not create after the submission deadline" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(hours: -1))
    attributes = FactoryBot.attributes_for(:proposal, call_id: @call.id)

    assert_no_difference("Admin::Proposals::Proposal.count") do
      post :create, params: { admin_proposals_proposal: attributes }
    end

    assert_includes flash[:error].first, "The submission deadline for #{@call.name} has been passed"
    assert_redirected_to admin_proposals_call_proposals_path(@call)
  end

  test "md_editor should render the question as the label" do
    question_text = "This is definitely not a duplicate question"
    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
    @call.questions.first.update(response_type: "Long Text", question_text:)

    proposal = FactoryBot.create(:proposal, call: @call)

    get :edit, params: { id: proposal }
    assert_response :success

    # The label bit is necessary because otherwise it will find the attribute and always match, even when the label is not visibly rendered
    assert_match %r{<p>#{question_text}</p>\n?</div></label>}, response.body
  end

  test "should update proposal" do
    sign_out @admin
    @call.update_attribute(:editing_deadline, DateTime.current.advance(days: 1))

    proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)

    proposal.users.first.add_role :admin
    sign_in proposal.users.first

    attributes = FactoryBot.attributes_for(:proposal, call_id: @call.id)

    team_members_count = 2
    attributes[:team_members_attributes] = generate_team_member_attributes(team_members_count)

    put :update, params: { id: proposal, admin_proposals_proposal: attributes }

    assert_enqueued_emails team_members_count

    assert_not_nil assigns(:proposal), "The update function did not set a proposal. There is probably something wrong with the authentication."

    assert_redirected_to admin_proposals_proposal_path(assigns(:proposal))
  end

  test "updating a proposal stores the team members in the order the rows were submitted" do
    sign_out @admin
    @call.update_attribute(:editing_deadline, DateTime.current.advance(days: 1))
    proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
    proposal.users.first.add_role :admin
    sign_in proposal.users.first
    first, second = proposal.team_members.order(:id).first(2)

    put :update, params: { id: proposal, admin_proposals_proposal: { team_members_attributes: {
      "0" => { id: second.id, user_id: second.user_id, position: second.position },
      "1" => { id: first.id, user_id: first.user_id, position: first.position }
    } } }
    assert_redirected_to admin_proposals_proposal_path(proposal)

    assert_equal 0, second.reload.display_order
    assert_equal 1, first.reload.display_order
  end

  test "should not email after updating when the editing deadline is passed" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -2))
    @call.update_attribute(:editing_deadline, DateTime.current.advance(days: -1))

    proposal = FactoryBot.create(:proposal, call: @call)

    attributes = FactoryBot.attributes_for(:proposal, call_id: @call.id)

    team_members_count = 2
    attributes[:team_members_attributes] = generate_team_member_attributes(team_members_count)

    put :update, params: { id: proposal, admin_proposals_proposal: attributes }

    assert_redirected_to admin_proposals_proposal_path(assigns(:proposal))

    assert_enqueued_emails 0
  end

  test "should not update invalid proposal" do
    sign_out @admin

    proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
    proposal.users.first.add_role :admin
    sign_in proposal.users.first

    attributes = FactoryBot.attributes_for(:proposal, publicity_text: nil, call_id: @call.id)

    put :update, params: { id: proposal, admin_proposals_proposal: attributes }

    assert_equal proposal.show_title, proposal.reload.show_title

    assert_response :unprocessable_entity
  end

  test "should destroy admin_proposals_proposal" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
    proposal = FactoryBot.create(:proposal, call: @call, team_member_count: 0)

    assert_difference("Admin::Proposals::Proposal.count", -1) do
      delete :destroy, params: { id: proposal }
    end

    assert_redirected_to admin_proposals_call_proposals_url(@call)
  end

  STATUS_ACTIONS = [
    # action, status before, withdrawn before, status after, withdrawn after, flash key, message
    [ :approve, :awaiting_approval, false, :approved, false, :success, "has been marked as approved." ],
    [ :approve, :approved, false, :approved, false, :error, "is not currently awaiting approval." ],
    [ :reject, :awaiting_approval, false, :rejected, false, :success, "has been marked as rejected." ],
    [ :reject, :successful, false, :successful, false, :error, "is not currently awaiting approval." ],
    [ :withdraw, :awaiting_approval, false, :awaiting_approval, true, :success, "has been withdrawn." ],
    [ :withdraw, :awaiting_approval, true, :awaiting_approval, true, :error, "is already withdrawn." ],
    [ :unwithdraw, :awaiting_approval, true, :awaiting_approval, false, :success, "is no longer withdrawn." ],
    [ :unwithdraw, :awaiting_approval, false, :awaiting_approval, false, :error, "is not withdrawn." ],
    [ :mark_successful, :approved, false, :successful, false, :success, "has been marked as successful." ],
    [ :mark_successful, :awaiting_approval, false, :awaiting_approval, false, :error, "is not currently approved." ],
    [ :mark_unsuccessful, :approved, false, :unsuccessful, false, :success, "has been marked as unsuccessful." ],
    [ :mark_unsuccessful, :successful, false, :successful, false, :error, "is not currently approved." ],
    [ :revert_status, :approved, false, :awaiting_approval, false, :success, "is now awaiting approval." ],
    [ :revert_status, :unsuccessful, false, :approved, false, :success, "is now approved." ]
  ].freeze

  STATUS_ACTIONS.each do |action, from, withdrawn, to, withdrawn_after, flash_key, message|
    test "#{action} on a #{'withdrawn ' if withdrawn}#{from} proposal" do
      @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
      proposal = FactoryBot.create(:proposal, call: @call, status: from, withdrawn: withdrawn)

      put action, params: { id: proposal.id }

      proposal.reload
      assert_equal [ to, withdrawn_after ], [ proposal.status, proposal.withdrawn ]
      assert_redirected_to admin_proposals_proposal_path(proposal)
      assert_equal [ "The #{get_object_name(proposal, include_class_name: true)} #{message}" ], flash[flash_key]
      assert_nil flash[flash_key == :success ? :error : :success]
    end
  end

  test "user without approve permission cannot change status via update" do
    sign_out @admin
    @call.update_attribute(:editing_deadline, DateTime.current.advance(days: 1))

    proposal = FactoryBot.create(:proposal, :with_team_members, call: @call, status: :awaiting_approval)
    # A team member on the proposal can update it, but should not have the :approve ability.
    updater = proposal.users.first
    sign_in updater

    attributes = FactoryBot.attributes_for(:proposal, call_id: @call.id)
    attributes[:status] = "approved"

    put :update, params: { id: proposal.id, admin_proposals_proposal: attributes }

    proposal.reload
    assert proposal.awaiting_approval?, "A user without the approve ability was able to set the proposal status via the update action."
  end

  test "convert" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
    proposal = FactoryBot.create(:proposal, call: @call, status: :successful)

    assert_difference "Show.count" do
      put :convert, params: { id: proposal.id }
    end

    assert Show.where(name: proposal.show_title).any?
    assert_redirected_to admin_proposals_proposal_path(proposal)
    assert_includes flash[:success].first, "is queued to be converted"
  end

  [ [ :awaiting_approval, false ], [ :rejected, false ], [ :successful, true ] ].each do |status, withdrawn|
    test "should not convert a #{'withdrawn ' if withdrawn}#{status} proposal" do
      @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
      proposal = FactoryBot.create(:proposal, call: @call, status:, withdrawn:)

      assert_no_difference "Show.count" do
        put :convert, params: { id: proposal.id }
      end

      assert_redirected_to admin_proposals_proposal_path(proposal)
      assert_equal [ "This proposal was not successful" ], flash[:error]
    end
  end

  test "about" do
    get :about

    assert_response :success
  end

  test "approve returns to a safe referrer and to the proposal otherwise" do
    @call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
    proposal = FactoryBot.create(:proposal, call: @call, status: :awaiting_approval)
    {
      admin_proposals_calls_path => admin_proposals_calls_path,
      admin_proposals_call_proposals_path(@call) => admin_proposals_call_proposals_path(@call),
      "https://evil.example.com" => admin_proposals_proposal_path(proposal)
    }.each do |referrer, expected|
      proposal.update!(status: :awaiting_approval)
      @request.headers["HTTP_REFERER"] = referrer

      put :approve, params: { id: proposal.id }

      assert_redirected_to expected
    end
  end

  private

  def generate_team_member_attributes(count)
    team_members_attributes = {}
    team_members = FactoryBot.build_list(:team_member, count)

    team_members.each_with_index do |team_member, index|
      team_member_attributes = team_member.attributes.except("id", "teamwork_id", "teamwork_type", "created_at", "updated_at")
      team_member_attributes[:user_id] = FactoryBot.create(:member).id
      team_members_attributes[index] = team_member_attributes
    end

    team_members_attributes
  end
end
