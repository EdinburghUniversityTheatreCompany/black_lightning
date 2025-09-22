# == Schema Information
#
# Table name: users
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *email*::                  <tt>string(255), default(""), not null</tt>
# *encrypted_password*::     <tt>string(255), default(""), not null</tt>
# *reset_password_token*::   <tt>string(255)</tt>
# *reset_password_sent_at*:: <tt>datetime</tt>
# *remember_created_at*::    <tt>datetime</tt>
# *sign_in_count*::          <tt>integer, default(0)</tt>
# *current_sign_in_at*::     <tt>datetime</tt>
# *last_sign_in_at*::        <tt>datetime</tt>
# *current_sign_in_ip*::     <tt>string(255)</tt>
# *last_sign_in_ip*::        <tt>string(255)</tt>
# *first_name*::             <tt>string(255)</tt>
# *last_name*::              <tt>string(255)</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *phone_number*::           <tt>string(255)</tt>
# *public_profile*::         <tt>boolean, default(TRUE)</tt>
# *bio*::                    <tt>text(65535)</tt>
# *avatar_file_name*::       <tt>string(255)</tt>
# *avatar_content_type*::    <tt>string(255)</tt>
# *avatar_file_size*::       <tt>integer</tt>
# *avatar_updated_at*::      <tt>datetime</tt>
# *username*::               <tt>string(255)</tt>
# *remember_token*::         <tt>string(255)</tt>
# *consented*::              <tt>date</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::UserTest < ActiveSupport::TestCase
  setup do
    @user = users(:user)
  end

  test "sort by first name" do
    FactoryBot.create :user

    assert_equal User.reorder("first_name ASC"), User.by_first_name
  end

  test "get ability" do
    assert @user.ability.is_a? Ability
  end

  test "has name" do
    assert @user.name?
    @user.update_attribute(:first_name, "")
    assert_not @user.name?
    @user.update!(first_name: "Finbar", last_name: nil)
    assert_not @user.name?
  end

  test "name or default" do
    assert_equal "#{@user.first_name} #{@user.last_name}", @user.name_or_default
    @user.update(first_name: "", last_name: "")
    assert_equal "No Name Set", @user.name_or_default
  end

  test "name or email" do
    assert_equal "#{@user.first_name} #{@user.last_name}", @user.name_or_email
    @user.update(first_name: "", last_name: "")
    assert_equal @user.email, @user.name_or_email
  end

  test "name" do
    assert_equal "#{@user.first_name} #{@user.last_name}", @user.name
    @user.update(first_name: "", last_name: "")
    assert_equal "No Name Set", @user.name

    admin = FactoryBot.create(:admin)

    assert_equal @user.email, @user.name(admin)
  end

  test "unify numbers" do
    @user.update_attribute(:phone_number, "07777")
    @user.unify_numbers
    assert_equal "+447777", @user.phone_number

    @user.update_attribute(:phone_number, "+317777")

    @user.unify_numbers
    assert_equal "+317777", @user.phone_number

    @user.update_attribute(:phone_number, "327777")
    @user.unify_numbers
    assert_equal "327777", @user.phone_number
  end

  test "create user" do
    attributes = { first_name: "Finbar", last_name: "the Viking", email: "finbar@viking.arrr" }
    user = User.new_user(attributes)
    assert_not user.password.blank?
    assert user.valid?

    attributes[:password] = "Hexagon"
    user = User.new_user(attributes)
    assert_equal "Hexagon", user.password
    assert user.valid?
  end

  # Debt
  test "debt causing and upcoming maintenance debts" do
    debt_causing_debt =      FactoryBot.create(:maintenance_debt,         user: @user)
    future_debt =            FactoryBot.create(:maintenance_debt,         user: @user, due_by: debt_causing_debt.due_by.advance(days: 2))
    _non_debt_causing_debt = FactoryBot.create(:overdue_maintenance_debt, user: @user, with_attendance: true)

    from_date = debt_causing_debt.due_by.advance(days: 2)
    assert_equal [ debt_causing_debt ], @user.debt_causing_maintenance_debts(from_date).to_a

    assert_equal [ future_debt ], @user.upcoming_maintenance_debts(from_date).to_a
  end

  test "debt causing and upcoming staffing debts" do
    debt_causing_debt =      FactoryBot.create :staffing_debt,         user: @user, admin_staffing_job_id: nil
    future_debt =            FactoryBot.create :staffing_debt,         user: @user, due_by: debt_causing_debt.due_by.advance(days: 2)
    _non_debt_causing_debt = FactoryBot.create :overdue_staffing_debt, user: @user, state: :forgiven

    from_date = debt_causing_debt.due_by.advance(days: 2)

    assert_equal [ debt_causing_debt.id ], @user.debt_causing_staffing_debts(from_date).ids

    assert_equal [ future_debt.id ], @user.upcoming_staffing_debts(from_date).ids
  end

  test "debt message suffix" do
    assert_equal "not in Debt", @user.debt_message_suffix
    staffing_debt = FactoryBot.create :overdue_staffing_debt, user: @user
    assert_equal "in staffing Debt", @user.debt_message_suffix
    FactoryBot.create :overdue_maintenance_debt, user: @user
    assert_equal "in staffing and maintenance Debt", @user.debt_message_suffix
    staffing_debt.delete
    assert_equal "in maintenance Debt", @user.debt_message_suffix
  end

  test "in debt" do
    assert_not @user.in_debt
    staffing_debt = FactoryBot.create :overdue_staffing_debt, user: @user
    assert @user.in_debt
    FactoryBot.create :overdue_maintenance_debt, user: @user
    assert @user.in_debt
    staffing_debt.delete
    assert @user.in_debt
  end

  test "users in debt" do
    FactoryBot.create :overdue_staffing_debt, user: @user
    FactoryBot.create :staffing_debt
    FactoryBot.create :maintenance_debt

    assert_equal [ @user ], User.in_debt.to_a
  end

  test "test notified since returns only users who are in debt and have not received a notification" do
    date = Date.current.advance(days: -7)

    # No notification.
    user_one = FactoryBot.create(:user)
    # One notification that is from before the date.
    user_two = FactoryBot.create(:user)
    FactoryBot.create(:initial_debt_notification, sent_on: date.advance(days: -1), user: user_two)
    # One notification that is on the date.
    user_three = FactoryBot.create(:user)
    FactoryBot.create(:initial_debt_notification, sent_on: date, user: user_three)
    # One notification that is after the date.
    user_four = FactoryBot.create(:user)
    FactoryBot.create(:initial_debt_notification, sent_on: date.advance(days: 1), user: user_four)

    notified_users = User.notified_since(date).to_a

    assert_not_includes notified_users, user_one, "The list of notified users includes the user without any notifications"
    assert_not_includes notified_users, user_two, "The list of notified users includes the user with a notification from before date"
    assert_not_includes notified_users, user_three, "The list of notified users includes the user with a notification on the date"
    assert_includes notified_users, user_four, "The list of notified users does not include the user that should be notified"
  end

  test "team memberships" do
    events = FactoryBot.create_list :show, 3, is_public: true
    user = events.first.users.first

    team_membership_without_teamwork = events.last.team_members.last

    assert_not_equal user, team_membership_without_teamwork.user

    team_membership_without_teamwork.update_attribute :teamwork_type, "Event"
    team_membership_without_teamwork.update_attribute :teamwork, nil

    team_memberships = user.team_memberships(true)

    teamworks = team_memberships.map(&:teamwork)

    assert_equal 1, teamworks.count

    assert_includes teamworks, events.first
  end

  test "consented" do
    @user.consented = Date.current
    assert @user.consented?

    @user.consented = Date.current.advance(years: -2)
    @user.save
    assert_not @user.consented?
  end

  test "add_role override" do
    role = Role.find_by(name: :member)

    assert_not @user.has_role?(role.name), "The user already has the role at the start, so the tests cannot be completed properly."

    @user.add_role(role)
    assert @user.has_role?(:member), "User does not have the role that was added as class instance"
  end

  test "has_role override" do
    role = Role.find_by(name: :member)
    @user.add_role(role.name)

    assert @user.has_role?(role.name), "Basemark check if the user has the member role failed"

    assert @user.has_role?(role), "The has_role? method override for the Role class does not work"
  end

  test "remove_role override" do
    role = Role.find_by(name: :member)
    @user.add_role(role.name)

    assert @user.has_role?(role.name), "Basemark check if the user has the member role failed"

    @user.remove_role(role)
    assert_not @user.has_role?(role.name), "The remove_role override for the Role class does not work."
  end

  test "email normalization" do
    # Input -> Expected Output
    pairs = [
      [ "j.appleseed@sms.ed.ac.uk", "j.appleseed@sms.ed.ac.uk" ],
      [ "s123456@sms.ed.ac.uk", "s123456@sms.ed.ac.uk" ],
      [ "STAFF.MEMBER@SMS.ED.AC.UK", "staff.member@sms.ed.ac.uk" ],
      [ "s1912811@sms.ed.ac.uk", "s1912811@ed.ac.uk" ]
    ]

    pairs.each do |pair|
      @user.email = pair[0]
      @user.save
      assert_equal pair[1], @user.email
    end
  end

  # User merge tests
  test "merge_user_into validates different users" do
    user = FactoryBot.create(:user)
    
    assert_raises(ArgumentError, /Source and target users cannot be the same/) do
      User.merge_user_into(user, user)
    end
  end
  test "merge_user_into transfers has_many relationships" do
    source_user = FactoryBot.create(:user)
    target_user = FactoryBot.create(:user)
    
    # Create some test data for source user
    staffing_job = FactoryBot.create(:staffing_job, user: source_user)
    maintenance_debt = FactoryBot.create(:maintenance_debt, user: source_user)
    staffing_debt = FactoryBot.create(:staffing_debt, user: source_user)
    
    original_target_relationships_count = target_user.staffing_jobs.count + target_user.admin_maintenance_debts.count + target_user.admin_staffing_debts.count
    
    User.merge_user_into(source_user, target_user)
    
    # Check relationships were transferred
    assert_includes target_user.staffing_jobs.reload, staffing_job
    assert_includes target_user.admin_maintenance_debts.reload, maintenance_debt  
    assert_includes target_user.admin_staffing_debts.reload, staffing_debt
    
    # Check source user was deleted
    assert_raises(ActiveRecord::RecordNotFound) { source_user.reload }
  end

  test "merge_user_into transfers roles" do
    source_user = FactoryBot.create(:user)
    target_user = FactoryBot.create(:user)
    
    # Add role to source user
    source_user.add_role(:member)
    
    assert source_user.has_role?(:member)
    assert_not target_user.has_role?(:member)
    
    User.merge_user_into(source_user, target_user)
    
    # Check role was transferred
    assert target_user.has_role?(:member)
    
    # Check source user was deleted
    assert_raises(ActiveRecord::RecordNotFound) { source_user.reload }
  end

  test "merge_user_into does not duplicate roles" do
    source_user = FactoryBot.create(:user)
    target_user = FactoryBot.create(:user)
    
    # Both users have the same role
    source_user.add_role(:member)
    target_user.add_role(:member)
    
    initial_member_role_count = Role.find_by(name: "member").users.count
    
    User.merge_user_into(source_user, target_user)
    
    # Check role count didn't increase
    assert_equal initial_member_role_count - 1, Role.find_by(name: "member").users.count
    assert target_user.has_role?(:member)
  end

  test "merge_user_into transfers single fields only when target is blank" do
    source_user = FactoryBot.create(:user, first_name: "Source", last_name: "User", phone_number: "123456789", bio: "Source bio")
    target_user = FactoryBot.create(:user, first_name: "Target", last_name: "", phone_number: "", bio: "")
    
    User.merge_user_into(source_user, target_user)
    
    target_user.reload
    # Should keep existing first_name, but take missing fields from source
    assert_equal "Target", target_user.first_name
    assert_equal "User", target_user.last_name
    assert_equal "123456789", target_user.phone_number
    assert_equal "Source bio", target_user.bio
  end

  test "merge_user_into handles public_profile correctly" do
    # Test 1: source has public_profile false, target true -> result should be false
    source_user = FactoryBot.create(:user, public_profile: false)
    target_user = FactoryBot.create(:user, public_profile: true)
    
    User.merge_user_into(source_user, target_user)
    
    target_user.reload
    assert_equal false, target_user.public_profile
    
    # Test 2: source has public_profile true, target false -> result should stay false
    source_user2 = FactoryBot.create(:user, public_profile: true)
    target_user2 = FactoryBot.create(:user, public_profile: false)
    
    User.merge_user_into(source_user2, target_user2)
    
    target_user2.reload
    assert_equal false, target_user2.public_profile
  end

  test "merge_user_into accumulates sign_in_count" do
    source_user = FactoryBot.create(:user, sign_in_count: 5)
    target_user = FactoryBot.create(:user, sign_in_count: 3)
    
    User.merge_user_into(source_user, target_user)
    
    target_user.reload
    assert_equal 8, target_user.sign_in_count
  end

  test "merge_user_into fails when both users have membership_card" do
    source_user = FactoryBot.create(:user)
    target_user = FactoryBot.create(:user)
    
    MembershipCard.create!(user: source_user)
    MembershipCard.create!(user: target_user)
    
    assert_raises(ActiveRecord::RecordInvalid, /both have a Membership Card/) do
      User.merge_user_into(source_user, target_user)
    end
  end

  test "merge_user_into transfers membership_card when target doesn't have one" do
    source_user = FactoryBot.create(:user)
    target_user = FactoryBot.create(:user)
    
    membership_card = MembershipCard.create!(user: source_user)
    
    User.merge_user_into(source_user, target_user)
    
    membership_card.reload
    assert_equal target_user, membership_card.user
  end

  test "merge_user_into fails when both users have marketing_creatives_profile" do
    source_user = FactoryBot.create(:user)
    target_user = FactoryBot.create(:user)
    
    FactoryBot.create(:marketing_creatives_profile, user: source_user)
    FactoryBot.create(:marketing_creatives_profile, user: target_user)
    
    assert_raises(ActiveRecord::RecordInvalid, /both have a Marketing Creatives Profile/) do
      User.merge_user_into(source_user, target_user)
    end
  end

  test "merge_user_into rolls back on failure" do
    source_user = FactoryBot.create(:user)
    target_user = FactoryBot.create(:user)
    
    # Create conflicting membership cards to trigger rollback
    MembershipCard.create!(user: source_user)
    MembershipCard.create!(user: target_user)
    
    staffing_job = FactoryBot.create(:staffing_job, user: source_user)
    
    assert_raises(ActiveRecord::RecordInvalid) do
      User.merge_user_into(source_user, target_user)
    end
    
    # Check that the transaction rolled back
    staffing_job.reload
    assert_equal source_user, staffing_job.user, "Staffing job should still belong to source user after rollback"
    assert_not_nil User.find(source_user.id), "Source user should still exist after rollback"
  end
end
