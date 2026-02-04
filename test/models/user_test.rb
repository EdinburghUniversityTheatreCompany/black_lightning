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
    events = FactoryBot.create_list :show, 3, is_public: true, team_member_count: 2
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

  test "student_id validation - valid formats" do
    valid_student_ids = [ "s1234567", "s9999999", nil, "" ]

    valid_student_ids.each do |student_id|
      @user.student_id = student_id
      assert @user.valid?, "#{student_id.inspect} should be valid but got errors: #{@user.errors.full_messages}"
    end
  end

  test "student_id validation - invalid formats" do
    invalid_student_ids = [ "1234567", "S1234567", "s123456", "s12345678", "student123", "s123456a" ]

    invalid_student_ids.each do |student_id|
      @user.student_id = student_id
      assert_not @user.valid?, "#{student_id.inspect} should be invalid"
      assert @user.errors[:student_id].any?, "Expected validation error on student_id for #{student_id.inspect}"
    end
  end

  test "student_id automatic extraction from email on create" do
    user = User.new(
      email: "s1234567@ed.ac.uk",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )
    user.save!

    assert_equal "s1234567", user.student_id
  end

  test "student_id automatic extraction from email on update" do
    @user.update!(email: "s9876543@ed.ac.uk")
    assert_equal "s9876543", @user.student_id
  end

  test "student_id extraction handles mixed case email" do
    @user.update!(email: "S7654321@ED.AC.UK")
    assert_equal "s7654321", @user.student_id
  end

  test "student_id not extracted from non-matching emails" do
    # Start with no student_id
    @user.update!(student_id: nil)

    non_matching_emails = [
      "staff@ed.ac.uk",
      "john@gmail.com",
      "j.appleseed@ed.ac.uk"
    ]

    non_matching_emails.each do |email|
      @user.update!(email: email)
      assert_nil @user.student_id, "student_id should remain nil for #{email}"
    end
  end

  test "manually set student_id is preserved" do
    @user.student_id = "s1111111"
    @user.email = "john@gmail.com"
    @user.save!

    assert_equal "s1111111", @user.student_id
  end

  test "duplicate student_ids are allowed" do
    @user.update!(email: "s1234567@ed.ac.uk")
    assert_equal "s1234567", @user.student_id

    # Create another user with a different email but manually set the same student_id
    user2 = FactoryBot.create(:user, email: "s9999999@ed.ac.uk")
    user2.update!(student_id: "s1234567")
    assert_equal "s1234567", user2.student_id

    # Both users should exist with the same student_id
    assert_equal 2, User.where(student_id: "s1234567").count
  end

  # Associate ID tests
  test "associate_id validation - valid formats" do
    valid_associate_ids = [ "ASSOC123456", "ASSOC1", "ASSOC999999999", nil, "" ]

    valid_associate_ids.each do |associate_id|
      @user.associate_id = associate_id
      assert @user.valid?, "#{associate_id.inspect} should be valid but got errors: #{@user.errors.full_messages}"
    end
  end

  test "associate_id validation - invalid formats" do
    # Note: "assoc123456" is valid because the normalizer converts it to uppercase before validation
    invalid_associate_ids = [ "123456", "ASSOC", "ASSOCIATE123", "A123456" ]

    invalid_associate_ids.each do |associate_id|
      @user.associate_id = associate_id
      assert_not @user.valid?, "#{associate_id.inspect} should be invalid"
      assert @user.errors[:associate_id].any?, "Expected validation error on associate_id for #{associate_id.inspect}"
    end
  end

  test "associate_id is normalized to uppercase" do
    @user.associate_id = "assoc213752"
    @user.save!

    assert_equal "ASSOC213752", @user.associate_id
  end

  test "associate_id is stripped of whitespace" do
    @user.associate_id = "  ASSOC123456  "
    @user.save!

    assert_equal "ASSOC123456", @user.associate_id
  end

  test "user can have both student_id and associate_id" do
    @user.student_id = "s1234567"
    @user.associate_id = "ASSOC123456"
    @user.save!

    assert_equal "s1234567", @user.student_id
    assert_equal "ASSOC123456", @user.associate_id
  end

  # Profile completion tests
  test "profile_completed_at can be set and read" do
    assert @user.respond_to?(:profile_completed_at), "User should have profile_completed_at attribute"

    timestamp = Time.current
    @user.update!(profile_completed_at: timestamp)

    assert_in_delta timestamp, @user.profile_completed_at, 1.second
  end

  test "profile_completed_at can be nil" do
    user = FactoryBot.create(:user)
    user.update_column(:profile_completed_at, nil)

    assert_nil user.profile_completed_at
  end

  test "profile_complete? returns true when profile_completed_at is present" do
    @user.update!(profile_completed_at: Time.current)

    assert @user.profile_complete?
  end

  test "profile_complete? returns false when profile_completed_at is nil" do
    @user.update_column(:profile_completed_at, nil)

    assert_not @user.profile_complete?
  end

  test "profile_incomplete? returns true when profile_completed_at is nil" do
    @user.update_column(:profile_completed_at, nil)

    assert @user.profile_incomplete?
  end

  test "profile_incomplete? returns false when profile_completed_at is present" do
    @user.update!(profile_completed_at: Time.current)

    assert_not @user.profile_incomplete?
  end

  test "complete_profile! sets profile_completed_at and consented" do
    @user.update_column(:profile_completed_at, nil)
    @user.update_column(:consented, nil)

    freeze_time do
      @user.complete_profile!

      assert_in_delta Time.current, @user.profile_completed_at, 1.second
      assert_equal Date.current, @user.consented
    end
  end

  test "complete_profile! updates consented even if already set" do
    old_consent_date = Date.current.advance(months: -6)
    @user.update_column(:consented, old_consent_date)
    @user.update_column(:profile_completed_at, nil)

    freeze_time do
      @user.complete_profile!

      assert_equal Date.current, @user.consented
      assert_not_equal old_consent_date, @user.consented
    end
  end

  test "profile_completion_token generates a valid signed token" do
    token = @user.profile_completion_token

    assert_not_nil token
    assert_kind_of String, token
    assert token.length > 20, "Token should be a substantial signed ID"
  end

  test "find_by_profile_completion_token finds user with valid token" do
    token = @user.profile_completion_token

    found_user = User.find_by_profile_completion_token(token)

    assert_equal @user, found_user
  end

  test "find_by_profile_completion_token returns nil for invalid token" do
    found_user = User.find_by_profile_completion_token("invalid_token")

    assert_nil found_user
  end

  test "find_by_profile_completion_token returns nil for expired token" do
    token = @user.profile_completion_token

    travel 8.days do
      found_user = User.find_by_profile_completion_token(token)

      assert_nil found_user
    end
  end

  test "find_by_profile_completion_token returns nil for token with wrong purpose" do
    # Generate a token with a different purpose
    wrong_purpose_token = @user.signed_id(purpose: :password_reset, expires_in: 7.days)

    found_user = User.find_by_profile_completion_token(wrong_purpose_token)

    assert_nil found_user
  end

  test "profile_incomplete scope returns users without profile_completed_at" do
    incomplete_user = FactoryBot.create(:user)
    incomplete_user.update_column(:profile_completed_at, nil)

    complete_user = FactoryBot.create(:user)
    complete_user.update!(profile_completed_at: Time.current)

    incomplete_users = User.profile_incomplete

    assert_includes incomplete_users, incomplete_user
    assert_not_includes incomplete_users, complete_user
  end

  test "profile_complete scope returns users with profile_completed_at" do
    incomplete_user = FactoryBot.create(:user)
    incomplete_user.update_column(:profile_completed_at, nil)

    complete_user = FactoryBot.create(:user)
    complete_user.update!(profile_completed_at: Time.current)

    complete_users = User.profile_complete

    assert_includes complete_users, complete_user
    assert_not_includes complete_users, incomplete_user
  end
end
