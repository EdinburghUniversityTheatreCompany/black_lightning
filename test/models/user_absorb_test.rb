require "test_helper"

class UserAbsorbTest < ActiveSupport::TestCase
  setup do
    @target_user = FactoryBot.create(:member)
    @source_user = FactoryBot.create(:member)
  end

  # Basic validation tests

  test "absorb returns error when trying to absorb self" do
    result = @target_user.absorb(@target_user)

    assert_not result[:success]
    assert_includes result[:errors], "Cannot merge user into itself"
  end

  test "absorb returns error when source user is nil" do
    result = @target_user.absorb(nil)

    assert_not result[:success]
    assert_includes result[:errors], "Source user not found"
  end

  # Team membership tests

  test "absorb transfers team memberships" do
    show = FactoryBot.create(:show)
    source_team_member = FactoryBot.create(:team_member, user: @source_user, teamwork: show, position: "Director")

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_includes @target_user.team_membership.reload.pluck(:teamwork_id), show.id
    assert_not User.exists?(@source_user.id), "Source user should be deleted"
  end

  test "absorb concatenates positions when both users are on same show" do
    show = FactoryBot.create(:show)
    FactoryBot.create(:team_member, user: @target_user, teamwork: show, position: "Director")
    FactoryBot.create(:team_member, user: @source_user, teamwork: show, position: "Producer")

    initial_count = @target_user.team_membership.count

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    # One membership per user per show, so the positions are joined with '/'.
    assert_equal initial_count, @target_user.team_membership.reload.count
    position = @target_user.team_membership.find_by(teamwork: show).position
    assert_equal "Director / Producer", position
  end

  # Staffing, debt and credit tests

  test "absorb moves staffing jobs, debts, notifications and credits to the target" do
    records = [
      FactoryBot.create(:staffing_job, user: @source_user),
      FactoryBot.create(:staffing_debt, user: @source_user),
      FactoryBot.create(:maintenance_debt, user: @source_user),
      FactoryBot.create(:initial_debt_notification, user: @source_user),
      FactoryBot.create(:maintenance_credit, user: @source_user)
    ]

    result = @target_user.absorb(@source_user)

    assert result[:success], result[:errors].inspect
    records.each { |record| assert_equal @target_user.id, record.reload.user_id, record.class.name }
    assert_equal 1, result[:transferred][:staffing_jobs]
    assert_equal 1, result[:transferred][:staffing_debts]
  end

  # Role tests

  test "absorb unions roles without duplicating them and never transfers Admin" do
    @source_user.add_role(:admin)
    @source_user.add_role(:committee)

    result = @target_user.absorb(@source_user)

    assert result[:success], result[:errors].inspect
    assert @target_user.has_role?(:committee)
    assert_not @target_user.has_role?(:admin)
    assert_equal 1, @target_user.roles.where(name: "Member").count
    assert_equal [ "Committee" ], result[:transferred][:roles]
  end

  # Email handling tests

  test "absorb takes the source's email only when the target holds an unknown_ placeholder" do
    [
      [ "unknown_1@bedlamtheatre.co.uk", "real1@example.com", "real1@example.com" ],
      [ "real2@example.com", "unknown_2@bedlamtheatre.co.uk", "real2@example.com" ],
      [ "unknown_3@bedlamtheatre.co.uk", "unknown_4@bedlamtheatre.co.uk", "unknown_3@bedlamtheatre.co.uk" ],
      [ "target@example.com", "source@example.com", "target@example.com" ]
    ].each do |target_email, source_email, expected|
      target = FactoryBot.create(:member, email: target_email)
      source = FactoryBot.create(:member, email: source_email)

      assert target.absorb(source)[:success]
      assert_equal expected, target.reload.email, "#{target_email} absorbing #{source_email}"
    end
  end

  # Field preference tests (keep_from_source parameter)

  test "absorb copies the fields named in keep_from_source" do
    @target_user.update!(first_name: "John", last_name: "Target", email: "target@example.com",
                         phone_number: "111", student_id: "s1111111", associate_id: "ASSOC111")
    @source_user.update!(first_name: "Jane", last_name: "Source", email: "source@example.com",
                         phone_number: "222", student_id: "s2222222", associate_id: "ASSOC222")

    result = @target_user.absorb(@source_user, keep_from_source: %w[name email phone_number student_id associate_id])

    assert result[:success], result[:errors].inspect
    assert_equal %w[Jane Source source@example.com 222 s2222222 ASSOC222],
                 @target_user.reload.attributes.values_at(*%w[first_name last_name email phone_number student_id associate_id])
  end

  test "absorb without keep_from_source keeps target fields by default" do
    @target_user.update!(first_name: "John", last_name: "Target")
    @source_user.update!(first_name: "Jane", last_name: "Source")

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    @target_user.reload
    assert_equal "John", @target_user.first_name
    assert_equal "Target", @target_user.last_name
  end

  # Cached duplicate tests

  test "absorb removes all cached duplicates involving source user" do
    user1 = FactoryBot.create(:member)
    user2 = FactoryBot.create(:member)
    user3 = FactoryBot.create(:member)

    dup1 = CachedDuplicate.create!(user1: @source_user, user2: user1, bucket_type: "overlapping")
    dup2 = CachedDuplicate.create!(user1: user2, user2: @source_user, bucket_type: "no_overlap")
    dup3 = CachedDuplicate.create!(user1: @source_user, user2: user3, bucket_type: "overlapping")
    dup_keep = CachedDuplicate.create!(user1: user1, user2: user2, bucket_type: "overlapping")

    result = @target_user.absorb(@source_user)

    assert result[:success], "Absorb should succeed: #{result[:errors]}"
    assert_not CachedDuplicate.exists?(dup1.id), "Cached duplicate 1 should be deleted"
    assert_not CachedDuplicate.exists?(dup2.id), "Cached duplicate 2 should be deleted"
    assert_not CachedDuplicate.exists?(dup3.id), "Cached duplicate 3 should be deleted"
    assert CachedDuplicate.exists?(dup_keep.id), "Unrelated cached duplicate should remain"
    assert_not User.exists?(@source_user.id), "Source user should be deleted"
  end

  # sms.ed.ac.uk emails

  test "absorb succeeds when source email is sms.ed.ac.uk variant of target email" do
    # Raw SQL bypasses the normalizes callback, to simulate data stored before the normalisation.
    target = FactoryBot.create(:user, email: "s9911001@ed.ac.uk")
    source = FactoryBot.create(:user)
    ActiveRecord::Base.connection.execute("UPDATE users SET email = 's9911001@sms.ed.ac.uk' WHERE id = #{source.id}")
    source.reload

    result = target.absorb(source)

    assert result[:success], result[:errors].inspect
    assert_raises(ActiveRecord::RecordNotFound) { source.reload }
  end

  test "absorb succeeds when source sms.ed.ac.uk email normalizes to email held by a third user" do
    # Raw SQL bypasses the normalizes callback; the third user must not be touched.
    third_user = FactoryBot.create(:user, email: "s9922002@ed.ac.uk")
    source     = FactoryBot.create(:user)
    ActiveRecord::Base.connection.execute("UPDATE users SET email = 's9922002@sms.ed.ac.uk' WHERE id = #{source.id}")
    source.reload
    target = FactoryBot.create(:user, email: "unknown_abc123@bedlamtheatre.co.uk")

    result = target.absorb(source)

    assert result[:success], result[:errors].inspect
    assert_raises(ActiveRecord::RecordNotFound) { source.reload }
    assert_equal "s9922002@ed.ac.uk", third_user.reload.email
  end
end
