require "test_helper"

# This is not actually a model, but it lives in the models folder.
class Admin::AbilityTest < ActiveSupport::TestCase
  setup do
    @user = users(:user)
    @ability = Ability.new @user
  end

  test "unspecified models have no permissions" do
    all_actions = %i[read show index edit update delete create new answer approve manage]

    models = ApplicationRecord.descendants
    exclusions = [ Admin::Debt, Admin::Feedback, Event, Show, Workshop, Season, News, Venue, Opportunity,
                  Admin::Questionnaires::Questionnaire, User, Admin::MaintenanceDebt, Admin::StaffingDebt,
                  Admin::Proposals::Proposal, Admin::Proposals::Call, MarketingCreatives::Profile, MarketingCreatives::CategoryInfo,
                  Complaint, Doorkeeper::Application, Attachment, VideoLink, Admin::EditableBlock, EventTag, Review, Picture, MaintenanceAttendance ]

    (models - exclusions).each do |model|
      helper_test_actions(model, model.name, @ability, [], all_actions)
    end
  end

  test "aliases" do
    # The action on the left is granted if the action on the right is granted.
    # For example: If you can delete, you can destroy, but if you can destroy, you can't necessarily delete.
    aliases = { destroy: :delete, edit: :update, grid: :read, reject: :approve }

    aliases.each do |action, action_alias|
      # The aliases for action method is private, but we need to access it for this test.
      assert_includes @ability.send(:aliases_for_action, action), action_alias, "The aliasses for #{action} does not include #{action_alias}"
    end
  end

  test "guests can read public news" do
    ability = Ability.new(nil)

    assert ability.can?(:read, FactoryBot.create(:news, show_public: true)), "Guests cannot read public news"
    assert ability.cannot?(:read, FactoryBot.create(:news, show_public: false)), "Guest can read news that is not public"
  end

  test "guests can read public events" do
    ability = Ability.new(nil)

    assert ability.can?(:read, FactoryBot.create(:show, is_public: true)), "Guests cannot see public shows"
    assert ability.cannot?(:read, FactoryBot.create(:show, is_public: false)), "Guest can see shows that are not public"

    assert ability.can?(:read, FactoryBot.create(:season, is_public: true)), "Guests cannot see public seasons"
    assert ability.cannot?(:read, FactoryBot.create(:season, is_public: false)), "Guest can see seasons that are not public"

    assert ability.can?(:read, FactoryBot.create(:workshop, is_public: true)), "Guests cannot see public workshops"
    assert ability.cannot?(:read, FactoryBot.create(:workshop, is_public: false)), "Guest can see workshopss that are not public"
  end

  test "users can read active opportunities" do
    active_opportunity = FactoryBot.create(:opportunity, approved: true, expiry_date: Date.current.advance(days: 1))
    inactive_opportunity = FactoryBot.create(:opportunity, approved: false)

    allowed_actions = %I[show read index]
    forbidden_actions = %I[update new create delete destroy]

    helper_test_actions(active_opportunity, "an active opportunity", @ability, allowed_actions, forbidden_actions)

    helper_test_actions(inactive_opportunity, "an inactive opportunity", @ability, [], allowed_actions + forbidden_actions)
  end

  test "guests can read and map venues" do
    allowed_actions = %I[show read index map]
    forbidden_actions = %I[update new create delete destroy]

    helper_test_actions(venues(:one), "a venue", @ability, allowed_actions, forbidden_actions)
  end

  test "test users have the correct permissions for users" do
    allowed_actions = %I[show debt_status update edit consent]
    forbidden_actions = %I[index read create check_membership destroy]

    helper_test_actions(@user, "itself", @ability, allowed_actions + [ :view_shows_and_bio ], forbidden_actions)

    public_user = FactoryBot.create :user, public_profile: true

    helper_test_actions(public_user, "another user with a public profile", @ability, [ :view_shows_and_bio ], allowed_actions + forbidden_actions)

    private_user = FactoryBot.create :user, public_profile: false

    helper_test_actions(private_user, "another user with a private profile", @ability, [], allowed_actions + forbidden_actions)
  end

  test "users can see debt status of users that are on the same proposal" do
    skip "This permission is no longer granted, but the test is still there for future reference."
    allowed_actions = %I[debt_status]
    # show edit update destroy
    forbidden_actions = %I[index read create check_membership]

    proposal = FactoryBot.create(:proposal)
    user = proposal.team_members.first.user
    ability = Ability.new(user)

    helper_test_actions(proposal.team_members.last.user, "an user with shared proposal", ability, allowed_actions, forbidden_actions)

    helper_test_actions(@user, "an user without shared proposal", ability, [], allowed_actions + forbidden_actions)
  end

  test "users have the correct proposal permissions before the submission deadline" do
    @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: 4))
    helper_set_up_proposal

    situation = "before the submission deadline"

    # 1A: Before the submission deadline, users can only see proposals that they are part of..
    helper_test_actions(@proposal, "@proposal#{situation}", @admin_ability, [ :create, :index ], @admin_abilities - [ :create, :index ])
    # .. but proposal checkers and admins cannot read.
    helper_test_proposal(:read, @proposal, false, true, false, situation)
    # 1B: Users edit current proposals they are on..
    helper_test_proposal(:update, @proposal, false, true, false, situation)
    # 1C: ..and create new proposals..
    helper_test_proposal(:create, @proposal, true, true, true, situation)
    # 1D: .. and cannot destroy proposals.
    helper_test_proposal(:delete, @proposal, false, false, false, situation)
  end

  test "users have the correct proposal permissions after the submission deadline / before the editing deadline" do
    @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: -1), editing_deadline: DateTime.current.advance(days: 1))
    helper_set_up_proposal
    situation = "after the submission deadline / before the editing deadline"

    # 2A: Before the editing deadline, users can only see proposals that they are part of..
    # .. or all if they are a proposal checker.
    helper_test_proposal(:read, @proposal, true, true, false, situation)
    # 2B: .. and edit existing proposals they are part of..
    helper_test_proposal(:update, @proposal, false, true, false, situation)
    # 2C: .. but cannot create new ones..
    helper_test_proposal(:create, @proposal, false, false, false, situation)
    # 2D: .. or destroy existing ones..
    helper_test_proposal(:delete, @proposal, false, false, false, situation)
    # 2E: .. and admins can now modify proposals.
    helper_test_actions(@proposal, "proposal #{situation}", @admin_ability, @admin_abilities, [])
  end

  test "users have the correct proposal permissions after the editing deadline for proposals awaiting approval" do
    @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: -2), editing_deadline: DateTime.current.advance(days: -1))
    helper_set_up_proposal
    @proposal.status = :awaiting_approval

    situation = "after the editing deadline when it is awaiting approval"

    # 3A: After the editing deadline while proposals are awaiting approval, users can only read proposals if they are a Proposal Checker or the ones that they are part of.
    helper_test_proposal(:read, @proposal, true, true, false, situation)
    # 3B: This is also the case when they have been rejected.
    @proposal.status = :rejected
    helper_test_proposal(:read, @proposal, true, true, false, situation)
  end

  test "users have the correct proposal permissions after the editing deadline for proposals that have been approved " do
    @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: -2), editing_deadline: DateTime.current.advance(days: -1))
    helper_set_up_proposal

    situation = "after the editing deadline, but that is approved"

    @proposal.status = :approved

    # 4A: Everyone can see proposals that have been approved...
    helper_test_proposal(:read, @proposal, true, true, true, situation)
    # 4B: ...and can no longer update proposals.
    helper_test_proposal(:update, @proposal, false, false, false, situation)

    # Same for successful and unsuccessful

    situation = "after the editing deadline, but that is successful"

    @proposal.status = :successful

    # 4A: Everyone can see proposals that have been approved...
    helper_test_proposal(:read, @proposal, true, true, true, situation)
    # 4B: ...and can no longer update proposals.
    helper_test_proposal(:update, @proposal, false, false, false, situation)



    situation = "after the editing deadline, but that is unsuccessful"

    @proposal.status = :unsuccessful

    # 4A: Everyone can see proposals that have been approved...
    helper_test_proposal(:read, @proposal, true, true, true, situation)
    # 4B: ...and can no longer update proposals.
    helper_test_proposal(:update, @proposal, false, false, false, situation)
  end

  test "users have the correct proposal permissions for archived proposals" do
    @call = FactoryBot.create(:proposal_call, archived: true, submission_deadline: DateTime.current.advance(days: -2), editing_deadline: DateTime.current.advance(days: -1))
    helper_set_up_proposal

    @proposal.status = :approved

    # 5A: People can see all archived proposals that are approved...
    # (Archiving only happens after both deadlines have passed)
    helper_test_proposal(:read, @proposal, true, true, true, "that is archived and approved")
    # 5B: ...or rejected ones that they were a part of...
    @proposal.status = :rejected
    helper_test_proposal(:read, @proposal, true, true, false, "that is archived but not approved")
    # 5C: ...and no one can edit archived proposals.
    helper_test_proposal(:update, @proposal, false, false, false, "that is archived but not approved")
  end

  test "users can access the proposal about page" do
    @call = FactoryBot.create(:proposal_call)
    helper_set_up_proposal
    # 6: Everyone can read the about page.
    helper_test_proposal(:about, @proposal, true, true, true, "that is archived but not approved")
  end

  test "have the correct call permissions" do
    allowed_actions = %I[show read index]
    forbidden_actions = %I[new create update delete]

    call = FactoryBot.create(:proposal_call)

    helper_test_actions(call, "a random proposal call", @ability, allowed_actions, forbidden_actions)
  end

  test "have the correct questionnaire permissions" do
    allowed_actions = %I[show answer read index]
    forbidden_actions = %I[new create update delete]

    questionnaire = FactoryBot.create :questionnaire, :with_team_members
    ability = Ability.new(questionnaire.event.team_members.first.user)

    helper_test_actions(questionnaire, "a questionnaire of a show they are on", ability, allowed_actions, forbidden_actions)

    other_questionnaire = FactoryBot.create :questionnaire

    helper_test_actions(other_questionnaire, "a questionnaire of a show they are not on", ability, [], allowed_actions + forbidden_actions)
  end

  test "users have the correct feedback permissions" do
    allowed_actions = %I[read]
    forbidden_actions = %I[update edit delete destroy create new]

    # Users can see feedbacks of shows they were involved in.
    feedback = FactoryBot.create :feedback, :with_team_members

    user = feedback.show.users.sample
    # If you do not do this, the user might accidentally get permissions from fixtures.
    user.remove_role(:member)

    ability = Ability.new user

    helper_test_actions(feedback, "feedback for own show", ability, allowed_actions, forbidden_actions)

    other_feedback = FactoryBot.create :feedback

    helper_test_actions(other_feedback, "feedback for other show", ability, [], allowed_actions + forbidden_actions)
  end

  test "users have the correct show permissions" do
    allowed_actions = %I[show update edit]
    forbidden_actions = %I[delete destroy create new]

    positions_that_can_update_shows = %w[Director Producer]

    # 1: test shows the user is not on.
    other_show = FactoryBot.create :show, is_public: false

    helper_test_actions(other_show, "other show", @ability, [], allowed_actions + forbidden_actions)

    # 2: Test shows the user is a director or producer on.
    show = FactoryBot.create :show, is_public: false, team_member_count: 1

    team_member = show.team_members.sample
    positions_that_can_update_shows.each do |position|
      team_member.position = position
      team_member.save

      ability = Ability.new(team_member.user)
      helper_test_actions(show, "show where they are #{position}", ability, allowed_actions, forbidden_actions)
    end

    # 3: Test shows the user is a hexagon on.
    hexagon_show = FactoryBot.create :show, is_public: false, team_member_count: 1

    hexagon_team_member = hexagon_show.team_members.sample
    hexagon_team_member.position = "Hexagon"
    team_member.save

    hexagon_ability = Ability.new(hexagon_team_member.user)
    helper_test_actions(other_show, "show where they are a hexagon", hexagon_ability, [], allowed_actions + forbidden_actions)
  end

  test "users have the correct debt permissions" do
    allowed_actions = %I[show]
    forbidden_actions = %I[index read update edit delete destroy create new]

    debt_class = Admin::Debt

    instance = helper_get_debt_instance(debt_class, @user.id)

    helper_test_actions(instance, "its own " + debt_class.name, @ability, allowed_actions, forbidden_actions)

    other_instance = helper_get_debt_instance(debt_class, @user.id + 1)

    helper_test_actions(other_instance, "another " + debt_class.name, @ability, [], allowed_actions + forbidden_actions)
  end

  test "users have the correct maintenance and staffing debt permissions" do
    allowed_actions = %I[read show index]
    forbidden_actions = %I[update edit delete destroy create new]

    debt_classes = [ Admin::MaintenanceDebt, Admin::StaffingDebt ]

    debt_classes.each do |debt_class|
      instance = helper_get_debt_instance(debt_class, @user.id)

      helper_test_actions(instance, "its own " + debt_class.name, @ability, allowed_actions, forbidden_actions)

      other_instance = helper_get_debt_instance(debt_class, @user.id + 1)

      helper_test_actions(other_instance, "another " + debt_class.name, @ability, [], allowed_actions + forbidden_actions)
    end
  end

  test "users can edit and read opportunities that they created" do
    allowed_actions = %I[show read index edit update]
    forbidden_actions = %I[new create delete destroy]

    created_opportunity = FactoryBot.create(:opportunity, approved: false)
    other_opportunity = FactoryBot.create(:opportunity, approved: false)

    ability = Ability.new(created_opportunity.creator)

    helper_test_actions(created_opportunity, "an opportunity they created", ability, allowed_actions, forbidden_actions)

    helper_test_actions(other_opportunity, "an opportuniy they did not create", ability, [], allowed_actions + forbidden_actions)
  end

  ##
  # Attachments
  ##

  test "everyone can see public attachments" do
    allowed_actions = %I[show]
    forbidden_actions = %I[read index edit update new create delete destroy]

    public_attachment = FactoryBot.create(:show_attachment, access_level: 2)

    helper_test_actions(public_attachment, "a public attachment", @ability, allowed_actions, forbidden_actions)
    helper_test_actions(public_attachment, "a public attachment as member", Ability.new(users(:member)), allowed_actions, forbidden_actions)
    helper_test_actions(public_attachment, "a public attachment as admin", Ability.new(users(:admin)), allowed_actions + forbidden_actions, [])
  end

  test "members can see member-only attachments" do
    allowed_actions = %I[show]
    forbidden_actions = %I[read index edit update new create delete destroy]

    members_only_attachment = FactoryBot.create(:editable_block_attachment, access_level: 1)

    helper_test_actions(members_only_attachment, "a members-only attachment", @ability, [], allowed_actions + forbidden_actions)
    helper_test_actions(members_only_attachment, "a members-only attachment as member", Ability.new(users(:member)), allowed_actions, forbidden_actions)
    helper_test_actions(members_only_attachment, "a members-only attachment as admin", Ability.new(users(:admin)), allowed_actions + forbidden_actions, [])
  end

  test "admins can see grid-based attachments" do
    forbidden_actions = %I[show read index edit update new create delete destroy]

    grid_based_attachment = FactoryBot.create(:show_attachment, access_level: 0)

    helper_test_actions(grid_based_attachment, "a grid-based attachment", @ability, [], forbidden_actions)
    helper_test_actions(grid_based_attachment, "a grid-based attachment as member", Ability.new(users(:member)), [], forbidden_actions)
    helper_test_actions(grid_based_attachment, "a grid-based attachment as admin", Ability.new(users(:admin)), forbidden_actions, [])
  end

  ##
  # Editable Blocks
  ##

  test "everyone can see non-admin site editable blocks" do
    allowed_actions = %I[show]
    forbidden_actions = %I[read index edit update new create delete destroy]

    public_editable_block = admin_editable_blocks(:public)

    public_editable_block.admin_page = [ nil, false ].sample

    helper_test_actions(public_editable_block, "a public editable block", @ability, allowed_actions, forbidden_actions)
    helper_test_actions(public_editable_block, "a public editable block as member", Ability.new(users(:member)), allowed_actions, forbidden_actions)
    helper_test_actions(public_editable_block, "a public editable block as admin", Ability.new(users(:admin)), allowed_actions + forbidden_actions, [])
  end

  test "members and admins can see non-admin site editable blocks" do
    allowed_actions = %I[show]
    forbidden_actions = %I[read index edit update new create delete destroy]

    admin_editable_block = admin_editable_blocks(:admin)

    helper_test_actions(admin_editable_block, "a admin editable block", @ability, [], allowed_actions + forbidden_actions)
    helper_test_actions(admin_editable_block, "a admin editable block as member", Ability.new(users(:member)), allowed_actions, forbidden_actions)
    helper_test_actions(admin_editable_block, "a admin editable block as admin", Ability.new(users(:admin)), allowed_actions + forbidden_actions, [])
  end

  ##
  # Marketing Creatives
  ##

  allowed_for_category_info = %I[read show index]
  forbidden_for_category_info = %I[edit update new create delete]

  test "users without an account can sign up and create a Marketing Creatives profile" do
    @ability = Ability.new(nil)

    allowed_actions = %I[sign_up create]
    forbidden_actions = %I[edit update show index new delete destroy approve reject]

    helper_test_actions(MarketingCreatives::Profile, "marketing creative profile as user without account", @ability, allowed_actions, forbidden_actions)
  end

  test "marketing_creatives profiles permissions for users with a profile" do
    allowed_actions = %I[show edit update reject sign_up create]
    forbidden_actions = %I[new delete destroy approve]

    profile = FactoryBot.create(:marketing_creatives_profile, approved: false)
    @user.marketing_creatives_profile = profile

    @ability = Ability.new @user.reload

    category_info = FactoryBot.create(:marketing_creatives_category_info, profile: profile)

    helper_test_actions(profile, "their own unapproved marketing creative profile", @ability, allowed_actions, forbidden_actions)
    helper_test_actions(category_info, "a category info for their own marketing creative profile", @ability, allowed_for_category_info, forbidden_for_category_info)

    # Cannot use the user fixture because it is already used for @user.
    random_ability = Ability.new(FactoryBot.create(:user))

    helper_test_actions(category_info, "a category info for a random marketing creative profile", random_ability, [], allowed_for_category_info + forbidden_for_category_info)
  end

  test "marketing_creatives permissions for someone elses approved profile" do
    allowed_actions = %I[sign_up create show]
    forbidden_actions = %I[index edit update new delete destroy approve reject]

    random_approved_profile = FactoryBot.create(:marketing_creatives_profile, approved: true)
    category_info_for_random_approved_profile = FactoryBot.create(:marketing_creatives_category_info, profile: random_approved_profile)

    helper_test_actions(random_approved_profile, "someone elses approved marketing creative profile", @ability, allowed_actions, forbidden_actions)
    helper_test_actions(category_info_for_random_approved_profile, "a category info for someone elses approved marketing creatives profile", @ability, allowed_for_category_info, forbidden_for_category_info)
  end

  test "marketing_creatives permissions for someone elses unapproved profile" do
    allowed_actions = %I[sign_up create]
    forbidden_actions = %I[index read show edit update new delete destroy approve reject]

    random_unapproved_profile = FactoryBot.create(:marketing_creatives_profile, approved: false)
    category_info_for_random_unapproved_profile = FactoryBot.create(:marketing_creatives_category_info, profile: random_unapproved_profile)

    helper_test_actions(random_unapproved_profile, "someone elses unapproved marketing creative profile", @ability, allowed_actions, forbidden_actions)
    helper_test_actions(category_info_for_random_unapproved_profile, "a category info for someone elses unapproved marketing creatives profile", @ability, [], allowed_for_category_info + forbidden_for_category_info)
  end

  test "marketing_creatives permissions for category_info when using the grid" do
    # Committee has a fixture that gives show permission for Marketing Creatives profiles.
    # This means we can test this by just testing if committee can see a category info belonging to an unapproved profile.

    allowed_actions = %I[sign_up create show]
    forbidden_actions = %I[index edit update new delete destroy approve reject]

    @ability = Ability.new(users(:committee))

    random_unapproved_profile = FactoryBot.create(:marketing_creatives_profile, approved: false)
    category_info_for_random_unapproved_profile = FactoryBot.create(:marketing_creatives_category_info, profile: random_unapproved_profile)

    description = "someone elses unapproved marketing creatives profile with show permission for the corresponding profile"

    helper_test_actions(random_unapproved_profile, description, @ability, allowed_actions, forbidden_actions)
    helper_test_actions(category_info_for_random_unapproved_profile, "a category info for " + description, @ability, allowed_for_category_info, forbidden_for_category_info)
  end

  ##
  # Complaints
  ##

  test "users can create complaint" do
    allowed_actions = %I[new create]
    forbidden_actions = %I[read show index edit update destroy]

    complaint = FactoryBot.create(:complaint)

    helper_test_actions(Complaint, "the complaint class as user", @ability, allowed_actions, forbidden_actions)

    ability = Ability.new(users(:committee))
    helper_test_actions(Complaint, "the complaint class as committee", ability, allowed_actions, forbidden_actions)
  end

  test "admins cannot do anything with complaints unless they have the correct permission" do
    admin = users(:admin)
    allowed_actions = %i[create new]
    # Granted by the welfare role
    semi_forbidden_actions = %i[read show index edit update]
    forbidden_actions = %I[destroy delete]
    ability = Ability.new(admin)

    helper_test_actions(Complaint, "the complaint class as an admin", ability, allowed_actions, semi_forbidden_actions + forbidden_actions)

    admin.add_role("Welfare Contact")

    ability = Ability.new(admin)

    helper_test_actions(Complaint, "the complaint class as an admin", ability, allowed_actions + semi_forbidden_actions, forbidden_actions)
  end

  test "permission grid permissions work" do
    # Pick classses for this that does not have any special permissions.
    # Please make sure the format of the Admin::Permission here is the same as the grid would use.

    role = Role.where(name: "member")
    other_role = [ Role.create(name: "pineapple") ]

    granted_permissions = [
      Admin::Permission.create(action: :read,   subject_class: "Role", roles: role),
      Admin::Permission.create(action: :update, subject_class: "Role", roles: role),
      Admin::Permission.create(action: :delete, subject_class: "MassMail", roles: role),
      Admin::Permission.create(action: :create, subject_class: "MassMail", roles: role)
    ]

    non_granted_permissions = [
      Admin::Permission.create(action: :delete, subject_class: "Role", roles: other_role),
      Admin::Permission.create(action: :edit,   subject_class: "Role", roles: other_role),
      Admin::Permission.create(action: :read,   subject_class: "MassMail", roles: other_role),
      Admin::Permission.create(action: :update, subject_class: "MassMail", roles: other_role)
    ]

    @user.add_role :member
    @ability = Ability.new(@user)

    other_user = FactoryBot.create :user, roles: other_role
    other_ability = Ability.new other_user

    granted_permissions.each do |permission|
      assert @ability.can?(permission.action.to_sym, permission.subject_class.constantize), "The user cannot perform the action :#{permission.action} on #{permission.subject_class} even though it should be able to"
      assert other_ability.cannot?(permission.action.to_sym, permission.subject_class.constantize), "The other user can perform the action :#{permission.action} on #{permission.subject_class} but it should not be able to"
    end
  end

  test "permission grid permissions works with manage" do
    # Pick a class without any special permissions.
    target_class = Role

    Admin::Permission.create(action: :manage, subject_class: target_class.name.to_s, roles: Role.where(name: "member"))
    @user.add_role :member
    ability = Ability.new @user

    allowed_actions = %I[index show new create edit update delete destroy hexagon pineapple]

    helper_test_actions(target_class, target_class.name, ability, allowed_actions, [])
  end

  private

  def helper_test_actions(target, target_name, ability, allowed_actions, forbidden_actions)
    allowed_actions.each do |action|
      assert ability.can?(action, target), "The user is not allowed to perform action :#{action} on #{target_name} while they should be able to"
    end

    forbidden_actions.each do |action|
      assert ability.cannot?(action, target), "The user is allowed to perform action :#{action} on #{target_name} while they should not be able to"
    end
  end

  def helper_get_debt_instance(debt_class, id)
    case debt_class.name
    when "Admin::Debt"
      Admin::Debt.new(id)
    when "Admin::MaintenanceDebt"
      FactoryBot.create :maintenance_debt, user_id: id
    when "Admin::StaffingDebt"
      FactoryBot.create :staffing_debt, user_id: id
    end
  end

  def helper_set_up_proposal
    assert_not_nil @call, "The call should be set before setting up the proposal"

    @admin_abilities = [ :update, :read, :create, :delete, :approve, :reject, :convert ].freeze
    @admin_ability = Ability.new(users(:admin))

    checker_user = FactoryBot.create(:user)
    checker_user.add_role "Proposal Checker"
    @checker_ability = Ability.new(checker_user)

    @random_ability = Ability.new(FactoryBot.create(:user))

    @proposal = @call.proposals.sample
    @proposal.status = :rejected

    @on_proposal_ability = Ability.new(@proposal.users.sample)
  end

  def helper_test_proposal(action, proposal, can_checker, can_on_proposal, can_random, situation)
    assert_equal can_checker,     @checker_ability.can?(action,     proposal), "Proposal Checkers #{correct_negative(can_checker)} :#{action} the proposal #{situation}"
    assert_equal can_on_proposal, @on_proposal_ability.can?(action, proposal), "A person on the proposal #{correct_negative(can_on_proposal)} :#{action} the proposal #{situation}"
    assert_equal can_random,      @random_ability.can?(action,      proposal), "A random person #{correct_negative(can_random)} :#{action} the proposal #{situation}"
  end

  def correct_negative(bool)
    bool ? "cannot" : "can"
  end
end
