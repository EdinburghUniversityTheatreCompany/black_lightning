require "test_helper"

class UserDuplicateDetectionTest < ActiveSupport::TestCase
  # years_active tests
  test "years_active returns empty array for user with no events" do
    user = FactoryBot.create(:user)
    assert_equal [], user.years_active
  end

  test "years_active returns academic years from events" do
    user = FactoryBot.create(:user)
    place_user_on_show(user, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))

    years = user.years_active
    assert_includes years, 2023, "Expected 2023 academic year (Oct 2023 is in 2023/24 academic year)"
  end

  test "years_active handles events spanning academic years" do
    user = FactoryBot.create(:user)
    # Show starting in August 2023 (2022/23 academic year) and ending in October 2023 (2023/24 academic year)
    place_user_on_show(user, start_date: Date.new(2023, 8, 15), end_date: Date.new(2023, 10, 1))

    years = user.years_active
    assert_includes years, 2022, "Expected 2022 academic year (Aug 2023 is in 2022/23)"
    assert_includes years, 2023, "Expected 2023 academic year (Oct 2023 is in 2023/24)"
  end

  # years_overlap? tests
  test "years_overlap returns true when users have overlapping activity" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    place_users_on_overlapping_shows(user1, user2)

    assert user1.years_overlap?(user2), "Users active in the same year should overlap"
  end

  test "years_overlap returns false when users are more than threshold years apart" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    place_users_on_non_overlapping_shows(user1, user2)

    assert_not user1.years_overlap?(user2), "Users 8 years apart should not overlap with default threshold of 4"
  end

  test "years_overlap returns true when either user has no activity data" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    place_user_on_show(user1, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))

    assert user1.years_overlap?(user2), "Should return true when one user has no activity data"
  end

  # mark_not_duplicate tests
  test "mark_not_duplicate does not add duplicate ids" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    user1.mark_not_duplicate(user2)
    user1.mark_not_duplicate(user2)

    assert_equal 1, user1.not_duplicate_user_ids.count(user2.id)
  end

  # marked_not_duplicate? tests
  test "marked_not_duplicate returns true when marked in either direction" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)
    assert_not user1.marked_not_duplicate?(user2)

    user1.mark_not_duplicate(user2)

    assert user1.marked_not_duplicate?(user2)
    assert user2.marked_not_duplicate?(user1), "Should work in reverse direction too"
  end

  # find_potential_duplicates tests
  test "find_potential_duplicates finds users sharing a student_id or associate_id" do
    { student_id: "s1234567", associate_id: "ASSOC123456" }.each do |column, value|
      user1 = FactoryBot.create(:user, column => value, last_name: "Smith", first_name: "John")
      user2 = FactoryBot.create(:user, column => value, last_name: "Doe", first_name: "Jane")

      same_id_matches = User.find_potential_duplicates[:same_id].select { |d| d[:id_value] == value }
      assert_equal 1, same_id_matches.size, column.to_s
      assert_includes same_id_matches.first[:users], user1
      assert_includes same_id_matches.first[:users], user2
    end
  end

  test "find_potential_duplicates finds users with equivalent sms and non-sms emails as definite duplicates" do
    user1 = FactoryBot.create(:user, email: "s1234567@ed.ac.uk")
    user2 = FactoryBot.create(:user)
    ActiveRecord::Base.connection.execute("UPDATE users SET email = 's1234567@sms.ed.ac.uk' WHERE id = #{user2.id}")

    duplicates = User.find_potential_duplicates

    same_id_matches = duplicates[:same_id].select { |d| d[:match_type] == :email && d[:id_value] == "s1234567@ed.ac.uk" }
    assert_equal 1, same_id_matches.size
    assert_includes same_id_matches.first[:users], user1
    assert_includes same_id_matches.first[:users], user2
  end

  test "find_potential_duplicates finds fuzzy name matches" do
    user1 = FactoryBot.create(:user, first_name: "Leonardo", last_name: "OConnor")
    user2 = FactoryBot.create(:user, first_name: "Leo", last_name: "OConnor")

    duplicates = User.find_potential_duplicates

    # Should be in overlapping bucket since neither has events (no data = assume possible match)
    fuzzy_matches = duplicates[:fuzzy_name_overlapping].select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_equal 1, fuzzy_matches.size
  end

  test "find_potential_duplicates matches last names that differ only in case" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "Zqxsmith")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "zqxsmith")

    duplicates = User.find_potential_duplicates

    assert(duplicates[:fuzzy_name_overlapping].any? { |d| d[:users].include?(user1) && d[:users].include?(user2) })
  end

  test "find_potential_duplicates excludes marked not-duplicates" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "TestSmith")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "TestSmith")

    user1.mark_not_duplicate(user2)

    duplicates = User.find_potential_duplicates

    all_fuzzy = duplicates[:fuzzy_name_overlapping] + duplicates[:fuzzy_name_non_overlapping]
    matches = all_fuzzy.select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_empty matches, "Marked not-duplicates should not appear in results"
  end

  # Merge helper methods tests

  test "overlapping_team_memberships_with returns count of shared shows" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    show1 = FactoryBot.create(:show)
    show2 = FactoryBot.create(:show)
    show3 = FactoryBot.create(:show)

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show1, position: "Director")
    TeamMember.create!(user: user1, teamwork: show2, position: "Stage Manager")
    TeamMember.create!(user: user2, teamwork: show2, position: "Producer")

    TeamMember.create!(user: user1, teamwork: show3, position: "Actor")

    assert_equal 2, user1.overlapping_team_memberships_with(user2)
    assert_equal 2, user2.overlapping_team_memberships_with(user1)
  end

  test "merge_stats_as_source returns totals, overlap and roles" do
    target = FactoryBot.create(:user)
    source = FactoryBot.create(:user)
    source.add_role(:member)

    show_a = FactoryBot.create(:show)
    show_b = FactoryBot.create(:show)
    TeamMember.create!(user: target, teamwork: show_a, position: "Director")
    TeamMember.create!(user: source, teamwork: show_a, position: "Actor")
    TeamMember.create!(user: source, teamwork: show_b, position: "Actor")

    stats = source.merge_stats_as_source(target)

    assert_equal 2, stats[:team_memberships][:total]
    assert_equal 1, stats[:team_memberships][:overlapping]
    assert_includes stats[:roles].map(&:downcase), "member"
  end
end
