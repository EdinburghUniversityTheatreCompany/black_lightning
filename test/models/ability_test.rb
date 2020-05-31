require 'test_helper'

# This is not actually a model, but it lives in the models folder.
class Admin::AbilityTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create :user
    @ability = Ability.new @user
  end

  test 'unspecified models have no permissions' do
    all_actions = %i[read show index edit update delete create new answer approve manage]

    models = ApplicationRecord.descendants
    exclusions = [Admin::Debt, Admin::Feedback, Event, Show, Workshop, Season, News, Venue, Opportunity,
                  Admin::Questionnaires::Questionnaire, User, Admin::MaintenanceDebt, Admin::StaffingDebt, 
                  Admin::Proposals::Proposal, Admin::Proposals::Call]

    (models - exclusions).each do |model|
      helper_test_actions(model, model.name, @ability, [], all_actions)
    end
  end

  test 'aliases' do
    # The action on the left is granted if the action on the right is granted.
    # For example: If you can delete, you can destroy, but if you can destroy, you can't necessarily delete.
    aliases = { destroy: :delete, edit: :update, grid: :read, reject: :approve, guidelines: :read }

    aliases.each do |action, action_alias|
      # The aliases for action method is private, but we need to access it for this test.
      assert_includes @ability.send(:aliases_for_action, action), action_alias, "The aliasses for #{action} does not include #{action_alias}"
    end
  end

  test 'guests can read public news' do
    ability = Ability.new(nil)

    assert ability.can?(:read, FactoryBot.create(:news, show_public: true)), 'Guests cannot read public news'
    assert ability.cannot?(:read, FactoryBot.create(:news, show_public: false)), 'Guest can read news that is not public'
  end

  test 'guests can read public events' do
    ability = Ability.new(nil)

    assert ability.can?(:read, FactoryBot.create(:show, is_public: true)), 'Guests cannot see public shows'
    assert ability.cannot?(:read, FactoryBot.create(:show, is_public: false)), 'Guest can see shows that are not public'

    assert ability.can?(:read, FactoryBot.create(:season, is_public: true)), 'Guests cannot see public seasons'
    assert ability.cannot?(:read, FactoryBot.create(:season, is_public: false)), 'Guest can see seasons that are not public'

    assert ability.can?(:read, FactoryBot.create(:workshop, is_public: true)), 'Guests cannot see public workshops'
    assert ability.cannot?(:read, FactoryBot.create(:workshop, is_public: false)), 'Guest can see workshopss that are not public'
  end

  test 'users can read active opportunities' do
    active_opportunity = FactoryBot.create(:opportunity, approved: true, expiry_date: Date.today.advance(days: 1))
    inactive_opportunity = FactoryBot.create(:opportunity, approved: false)

    allowed_actions = %I[show read index]
    forbidden_actions = %I[update new create delete destroy]

    helper_test_actions(active_opportunity, 'an active opportunity', @ability, allowed_actions, forbidden_actions)

    helper_test_actions(inactive_opportunity, 'an inactive opportunity', @ability, [], allowed_actions + forbidden_actions)
  end

  test 'guests can read venues' do
    allowed_actions = %I[show read index]
    forbidden_actions = %I[update new create delete destroy]

    helper_test_actions(venues(:one), 'a venue', @ability, allowed_actions, forbidden_actions)
  end

  test 'test users have the correct permissions for users' do
    allowed_actions = %I[show debt_status update edit]
    forbidden_actions = %I[index read create assign_roles check_membership destroy]

    helper_test_actions(@user, 'itself', @ability, allowed_actions + [:view_public_profile], forbidden_actions)

    public_user = FactoryBot.create :user, public_profile: true

    helper_test_actions(public_user, 'another user with a public profile', @ability, [:view_public_profile], allowed_actions + forbidden_actions)

    private_user = FactoryBot.create :user, public_profile: false

    helper_test_actions(private_user, 'another user with a private profile', @ability, [], allowed_actions + forbidden_actions)
  end

  test 'users can see debt status of users that are on the same proposal' do
    skip 'This permission is no longer granted, but the test is still there for future reference.'
    allowed_actions = %I[debt_status]
    # show edit update destroy
    forbidden_actions = %I[index read create assign_roles check_membership]

    proposal = FactoryBot.create(:proposal)
    user = proposal.team_members.first.user
    ability = Ability.new(user)

    helper_test_actions(proposal.team_members.last.user, 'an user with shared proposal', ability, allowed_actions, forbidden_actions)

    helper_test_actions(@user, 'an user without shared proposal', ability, [], allowed_actions + forbidden_actions)
  end

  test 'users have the correct proposal permissions' do
    admin_abilities = [:update, :read, :create, :delete, :approve, :reject, :convert].freeze
    @admin_ability = Ability.new(users(:admin))

    # Proposal Checkers can always see all proposals (they have proposal :read). This permission is a fixture.
    # Test that that still stays valid even in the different scenarios.
    checker_user = FactoryBot.create(:user)
    checker_user.add_role 'Proposal Checker'
    @checker_ability = Ability.new(checker_user)

    @random_ability = Ability.new(FactoryBot.create(:user))

    call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.now.advance(days: 4))

    proposal = call.proposals.sample

    @on_proposal_ability = Ability.new(proposal.users.sample)

    situation = 'before the submission deadline'

    # 1A: Before the submission deadline, users can only see proposals that they are part of..
    # .. proposal checkers and admins cannot read..
    helper_test_proposal(:read, proposal, false, true, false, situation)
    helper_test_actions(proposal, "proposal #{situation}", @admin_ability, [], admin_abilities)
    # 1B: Users edit current proposals..
    helper_test_proposal(:update, proposal, false, true, false, situation)
    # 1C: ..and create new proposals..
    helper_test_proposal(:create, proposal, true, true, true, situation)
    # 1D: .. and cannot destroy proposals.
    helper_test_proposal(:delete, proposal, false, false, false, situation)

    call.update_attribute(:submission_deadline, DateTime.now.advance(days: -1))
    situation = 'after the submission deadline / before the editing deadline'

    # 2A: Before the editing deadline, users can only see proposals that they are part of..
    # .. or all if they are a proposal checker.
    helper_test_proposal(:read, proposal, true, true, false, situation)
    # 2B: .. and edit existing proposals they are part of..
    helper_test_proposal(:update, proposal, false, true, false, situation)
    # 2C: .. but cannot create new ones..
    helper_test_proposal(:create, proposal, false, false, false, situation)
    # 2D: .. or destroy existing ones..
    helper_test_proposal(:delete, proposal, false, false, false, situation)
    # 2E: .. and admins can now modify proposals.
    helper_test_actions(proposal, "proposal #{situation}", @admin_ability, admin_abilities, [])

    call.update_attribute(:editing_deadline, DateTime.now.advance(days: -1))
    situation = 'after the editing deadline'

    # 3A: After the editing deadline, users can only read proposals if they are a Proposal Checker or the ones that they are part of..
    helper_test_proposal(:read, proposal, true, true, false, situation)
    # 3B: .. including when they have been rejected.
    proposal.approved = false
    helper_test_proposal(:read, proposal, true, true, false, situation)

    # 4A: Everyone can see the ones that have been approved...
    proposal.approved = true
    situation = "#{situation}, but that is approved"
    helper_test_proposal(:read, proposal, true, true, true, situation)
    # 4B: ...and can no longer update proposals.
    helper_test_proposal(:update, proposal, false, false, false, situation)

    # 5A: People can see all archived proposals that are approved...
    # (Archiving only happens after both deadlines have passed)
    call.archived = true
    proposal.approved = true
    helper_test_proposal(:read, proposal, true, true, true, 'that is archived and approved')
    # 5B: ...or rejected ones that they were a part of...
    proposal.approved = false
    helper_test_proposal(:read, proposal, true, true, false, 'that is archived but not approved')
    # 5C: ...and no one can edit archived proposals.
    helper_test_proposal(:update, proposal, false, false, false, 'that is archived but not approved')

    # 6: Everyone can read the about page.
    helper_test_proposal(:about, proposal, true, true, true, 'that is archived but not approved')
  end

  test 'have the correct call permissions' do
    allowed_actions = %I[show read index]
    forbidden_actions = %I[new create update delete]

    call = FactoryBot.create(:proposal_call)

    helper_test_actions(call, 'a random proposal call', @ability, allowed_actions, forbidden_actions)
  end

  test 'have the correct questionnaire permissions' do
    allowed_actions = %I[show answer read index]
    forbidden_actions = %I[new create update delete]

    questionnaire = FactoryBot.create :questionnaire
    ability = Ability.new(questionnaire.show.team_members.first.user)

    helper_test_actions(questionnaire, 'a questionnaire of a show they are on', ability, allowed_actions, forbidden_actions)

    other_questionnaire = FactoryBot.create :questionnaire

    helper_test_actions(other_questionnaire, 'a questionnaire of a show they are not on', ability, [], allowed_actions + forbidden_actions)
  end

  test 'users have the correct feedback permissions' do
    allowed_actions = %I[read]
    forbidden_actions = %I[update edit delete destroy create new]

    # Users can see feedbacks of shows they were involved in.
    feedback = FactoryBot.create :feedback

    user = feedback.show.users.sample
    # If you do not do this, the user might accidentally get permissions from fixtures.
    user.remove_role(:member)

    ability = Ability.new user

    helper_test_actions(feedback, 'feedback for own show', ability, allowed_actions, forbidden_actions)

    other_feedback = FactoryBot.create :feedback

    helper_test_actions(other_feedback, 'feedback for other show', ability, [], allowed_actions + forbidden_actions)
  end

  test 'users have the correct show permissions' do
    allowed_actions = %I[show update edit]
    forbidden_actions = %I[delete destroy create new]

    positions_that_can_update_shows = %w[Director Producer]

    # 1: test shows the user is not on.
    other_show = FactoryBot.create :show, is_public: false

    helper_test_actions(other_show, 'other show', @ability, [], allowed_actions + forbidden_actions)

    # 2: Test shows the user is a director or producer on.
    show = FactoryBot.create :show, is_public: false

    team_member = show.team_members.sample
    positions_that_can_update_shows.each do |position|
      team_member.position = position
      team_member.save

      ability = Ability.new(team_member.user)
      helper_test_actions(show, "show where they are #{position}", ability, allowed_actions, forbidden_actions)
    end

    # 3: Test shows the user is a hexagon on.
    hexagon_show = FactoryBot.create :show, is_public: false

    hexagon_team_member = hexagon_show.team_members.sample
    hexagon_team_member.position = 'Hexagon'
    team_member.save

    hexagon_ability = Ability.new(hexagon_team_member.user)
    helper_test_actions(other_show, 'show where they are a hexagon', hexagon_ability, [], allowed_actions + forbidden_actions)
  end

  test 'users have the correct debt permissions' do
    allowed_actions = %I[show]
    forbidden_actions = %I[index read update edit delete destroy create new]

    debt_class = Admin::Debt

    instance = helper_get_debt_instance(debt_class, @user.id)

    helper_test_actions(instance, 'its own ' + debt_class.name, @ability, allowed_actions, forbidden_actions)

    other_instance = helper_get_debt_instance(debt_class, @user.id + 1)

    helper_test_actions(other_instance, 'another ' + debt_class.name, @ability, [], allowed_actions + forbidden_actions)
  end

  test 'users have the correct maintenance and staffing debt permissions' do
    allowed_actions = %I[read show index]
    forbidden_actions = %I[update edit delete destroy create new]

    debt_classes = [Admin::MaintenanceDebt, Admin::StaffingDebt]

    debt_classes.each do |debt_class|
      instance = helper_get_debt_instance(debt_class, @user.id)

      helper_test_actions(instance, 'its own ' + debt_class.name, @ability, allowed_actions, forbidden_actions)

      other_instance = helper_get_debt_instance(debt_class, @user.id + 1)

      helper_test_actions(other_instance, 'another ' + debt_class.name, @ability, [], allowed_actions + forbidden_actions)
    end
  end

  test 'users can edit and read opportunities that they created' do
    allowed_actions = %I[show read index edit update]
    forbidden_actions = %I[new create delete destroy]

    created_opportunity = FactoryBot.create(:opportunity, approved: false)
    other_opportunity = FactoryBot.create(:opportunity, approved: false)

    ability = Ability.new(created_opportunity.creator)

    helper_test_actions(created_opportunity, 'an opportunity they created', ability, allowed_actions, forbidden_actions)

    helper_test_actions(other_opportunity, 'an opportuniy they did not create', ability, [], allowed_actions + forbidden_actions)
  end

  test 'permission grid permissions work' do
    # Pick classses for this that does not have any special permissions.
    # Please make sure the format of the Admin::Permission here is the same as the grid would use.

    role = Role.where(name: 'member')
    other_role = [Role.create(name: 'pineapple')]

    granted_permissions = [
      Admin::Permission.create(action: :read,   subject_class: 'Role', roles: role),
      Admin::Permission.create(action: :update, subject_class: 'Role', roles: role),
      Admin::Permission.create(action: :delete, subject_class: 'MassMail', roles: role),
      Admin::Permission.create(action: :create, subject_class: 'MassMail', roles: role)
    ]

    non_granted_permissions = [
      Admin::Permission.create(action: :delete, subject_class: 'Role', roles: other_role),
      Admin::Permission.create(action: :edit,   subject_class: 'Role', roles: other_role),
      Admin::Permission.create(action: :read,   subject_class: 'MassMail', roles: other_role),
      Admin::Permission.create(action: :update, subject_class: 'MassMail', roles: other_role)
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

  test 'permission grid permissions works with manage' do
    # Pick a class without any special permissions.
    target_class = Role

    Admin::Permission.create(action: :manage, subject_class: target_class.name.to_s, roles: Role.where(name: 'member'))
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
    when 'Admin::Debt'
      return Admin::Debt.new(id)
    when 'Admin::MaintenanceDebt'
      return FactoryBot.create :maintenance_debt, user_id: id
    when 'Admin::StaffingDebt'
      return FactoryBot.create :staffing_debt, user_id: id
    end
  end

  def helper_test_proposal(action, proposal, can_checker, can_on_proposal, can_random, situation)
    assert_equal can_checker,     @checker_ability.can?(action,     proposal), "Proposal Checkers #{correct_negative(can_checker)} :#{action} the proposal #{situation}"
    assert_equal can_on_proposal, @on_proposal_ability.can?(action, proposal), "A person on the proposal #{correct_negative(can_on_proposal)} :#{action} the proposal #{situation}"
    assert_equal can_random,      @random_ability.can?(action,      proposal), "A random person #{correct_negative(can_random)} :#{action} the proposal #{situation}"
  end

  def correct_negative(bool)
    return bool ? 'cannot' : 'can'
  end
end