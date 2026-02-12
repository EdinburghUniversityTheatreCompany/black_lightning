require "test_helper"

class UserDuplicateDetectionTest < ActiveSupport::TestCase
  setup do
    @user = users(:user)
  end

  # years_active tests
  test "years_active returns empty array for user with no events" do
    user = FactoryBot.create(:user)
    assert_equal [], user.years_active
  end

  test "years_active returns academic years from events" do
    user = FactoryBot.create(:user)
    # Create a show with this user as a team member
    show = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))

    # The show should have team members by default from the factory
    # Add our user to the show
    TeamMember.create!(user: user, teamwork: show, position: "Actor")

    years = user.years_active
    assert_includes years, 2023, "Expected 2023 academic year (Oct 2023 is in 2023/24 academic year)"
  end

  test "years_active handles events spanning academic years" do
    user = FactoryBot.create(:user)
    # Show starting in August 2023 (2022/23 academic year) and ending in October 2023 (2023/24 academic year)
    show = FactoryBot.create(:show, start_date: Date.new(2023, 8, 15), end_date: Date.new(2023, 10, 1))
    TeamMember.create!(user: user, teamwork: show, position: "Actor")

    years = user.years_active
    assert_includes years, 2022, "Expected 2022 academic year (Aug 2023 is in 2022/23)"
    assert_includes years, 2023, "Expected 2023 academic year (Oct 2023 is in 2023/24)"
  end

  # years_overlap? tests
  test "years_overlap returns true when users have overlapping activity" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    show1 = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))
    show2 = FactoryBot.create(:show, start_date: Date.new(2023, 11, 1), end_date: Date.new(2023, 11, 5))

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show2, position: "Actor")

    assert user1.years_overlap?(user2), "Users active in the same year should overlap"
  end

  test "years_overlap returns false when users are more than threshold years apart" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    show1 = FactoryBot.create(:show, start_date: Date.new(2015, 10, 1), end_date: Date.new(2015, 10, 5))
    show2 = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show2, position: "Actor")

    assert_not user1.years_overlap?(user2), "Users 8 years apart should not overlap with default threshold of 4"
  end

  test "years_overlap returns true when either user has no activity data" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    show = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))
    TeamMember.create!(user: user1, teamwork: show, position: "Actor")

    # user2 has no events
    assert user1.years_overlap?(user2), "Should return true when one user has no activity data"
  end

  # mark_not_duplicate tests
  test "mark_not_duplicate adds other user id to not_duplicate_user_ids" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    user1.mark_not_duplicate(user2)

    assert_includes user1.not_duplicate_user_ids, user2.id
  end

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

    user1.mark_not_duplicate(user2)

    assert user1.marked_not_duplicate?(user2)
    assert user2.marked_not_duplicate?(user1), "Should work in reverse direction too"
  end

  test "marked_not_duplicate returns false when not marked" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    assert_not user1.marked_not_duplicate?(user2)
  end

  # fuzzy_first_name_match? tests
  test "fuzzy_first_name_match returns true for exact match" do
    assert User.fuzzy_first_name_match?("John", "John")
  end

  test "fuzzy_first_name_match returns true for case insensitive match" do
    assert User.fuzzy_first_name_match?("JOHN", "john")
  end

  test "fuzzy_first_name_match returns true for abbreviations" do
    assert User.fuzzy_first_name_match?("Leo", "Leonardo")
    assert User.fuzzy_first_name_match?("Leonardo", "Leo")
  end

  test "fuzzy_first_name_match returns true for similar names" do
    assert User.fuzzy_first_name_match?("John", "Jon")
    assert User.fuzzy_first_name_match?("Michael", "Micheal")
  end

  test "fuzzy_first_name_match returns false for very different names" do
    assert_not User.fuzzy_first_name_match?("John", "Sarah")
    assert_not User.fuzzy_first_name_match?("Michael", "David")
  end

  test "fuzzy_first_name_match handles special characters" do
    assert User.fuzzy_first_name_match?("O'Brien", "OBrien")
    assert User.fuzzy_first_name_match?("Jean-Pierre", "JeanPierre")
  end

  # fuzzy_last_name_match? tests
  test "fuzzy_last_name_match returns true for exact match" do
    assert User.fuzzy_last_name_match?("Smith", "Smith")
  end

  test "fuzzy_last_name_match returns true for similar last names" do
    assert User.fuzzy_last_name_match?("Turnbull", "Trunbull")
    assert User.fuzzy_last_name_match?("Johnson", "Jonson")
  end

  test "fuzzy_last_name_match returns false for very different last names" do
    assert_not User.fuzzy_last_name_match?("Smith", "Jones")
    assert_not User.fuzzy_last_name_match?("Turnbull", "Anderson")
  end

  test "fuzzy_last_name_match handles special characters" do
    assert User.fuzzy_last_name_match?("O'Brien", "OBrien")
    assert User.fuzzy_last_name_match?("Smith-Jones", "SmithJones")
  end

  test "fuzzy_last_name_match returns false for blank names" do
    assert_not User.fuzzy_last_name_match?("", "Smith")
    assert_not User.fuzzy_last_name_match?("Smith", "")
    assert_not User.fuzzy_last_name_match?(nil, "Smith")
  end

  # find_potential_duplicates tests
  test "find_potential_duplicates finds users with same student_id" do
    user1 = FactoryBot.create(:user, student_id: "s1234567", last_name: "Smith", first_name: "John")
    user2 = FactoryBot.create(:user, student_id: "s1234567", last_name: "Doe", first_name: "Jane")

    duplicates = User.find_potential_duplicates

    same_id_matches = duplicates[:same_id].select { |d| d[:id_value] == "s1234567" }
    assert_equal 1, same_id_matches.size
    assert_includes same_id_matches.first[:users], user1
    assert_includes same_id_matches.first[:users], user2
  end

  test "find_potential_duplicates finds users with same associate_id" do
    user1 = FactoryBot.create(:user, associate_id: "ASSOC123456", last_name: "Smith", first_name: "John")
    user2 = FactoryBot.create(:user, associate_id: "ASSOC123456", last_name: "Doe", first_name: "Jane")

    duplicates = User.find_potential_duplicates

    same_id_matches = duplicates[:same_id].select { |d| d[:id_value] == "ASSOC123456" }
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

  # Bucket 4: Fuzzy both names + overlapping years tests
  test "find_potential_duplicates finds fuzzy both names with overlapping years" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    # Both users have no events, so years_overlap? returns true (no data = assume possible match)
    duplicates = User.find_potential_duplicates

    fuzzy_both_matches = duplicates[:fuzzy_both_overlapping].select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_equal 1, fuzzy_both_matches.size
  end

  test "find_potential_duplicates fuzzy both names with actual overlapping events" do
    user1 = FactoryBot.create(:user, first_name: "Leo", last_name: "Johnson")
    user2 = FactoryBot.create(:user, first_name: "Leon", last_name: "Jonson")

    show1 = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))
    show2 = FactoryBot.create(:show, start_date: Date.new(2023, 11, 1), end_date: Date.new(2023, 11, 5))

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show2, position: "Actor")

    duplicates = User.find_potential_duplicates

    fuzzy_both_matches = duplicates[:fuzzy_both_overlapping].select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_equal 1, fuzzy_both_matches.size
  end

  # Bucket 5: Fuzzy both names + no overlapping years tests
  test "find_potential_duplicates finds fuzzy both names without overlapping years" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    show1 = FactoryBot.create(:show, start_date: Date.new(2015, 10, 1), end_date: Date.new(2015, 10, 5))
    show2 = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show2, position: "Actor")

    duplicates = User.find_potential_duplicates

    fuzzy_both_matches = duplicates[:fuzzy_both_no_overlap].select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_equal 1, fuzzy_both_matches.size
  end

  # Mutual exclusivity tests
  test "find_potential_duplicates does not put exact last name matches in fuzzy_both buckets" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "TestMutex")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "TestMutex")

    duplicates = User.find_potential_duplicates

    # Should be in fuzzy_name_overlapping (bucket 2), not fuzzy_both
    fuzzy_exact_last = duplicates[:fuzzy_name_overlapping].select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_equal 1, fuzzy_exact_last.size, "Exact last name match should be in bucket 2"

    # Should NOT be in fuzzy_both buckets
    all_fuzzy_both = duplicates[:fuzzy_both_overlapping] + duplicates[:fuzzy_both_no_overlap]
    fuzzy_both_matches = all_fuzzy_both.select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_empty fuzzy_both_matches, "Exact last name matches should not appear in fuzzy_both buckets"
  end

  test "find_potential_duplicates excludes marked not-duplicates from fuzzy_both buckets" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    user1.mark_not_duplicate(user2)

    duplicates = User.find_potential_duplicates

    all_fuzzy_both = duplicates[:fuzzy_both_overlapping] + duplicates[:fuzzy_both_no_overlap]
    matches = all_fuzzy_both.select do |d|
      d[:users].include?(user1) && d[:users].include?(user2)
    end
    assert_empty matches, "Marked not-duplicates should not appear in fuzzy_both buckets"
  end

  # Merge helper methods tests

  test "overlapping_team_memberships_with returns count of shared shows" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    show1 = FactoryBot.create(:show)
    show2 = FactoryBot.create(:show)
    show3 = FactoryBot.create(:show)

    # Both users on show1 and show2
    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show1, position: "Director")
    TeamMember.create!(user: user1, teamwork: show2, position: "Stage Manager")
    TeamMember.create!(user: user2, teamwork: show2, position: "Producer")

    # Only user1 on show3
    TeamMember.create!(user: user1, teamwork: show3, position: "Actor")

    assert_equal 2, user1.overlapping_team_memberships_with(user2)
    assert_equal 2, user2.overlapping_team_memberships_with(user1)
  end

  test "overlapping_team_memberships_with returns 0 when no shared shows" do
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    show1 = FactoryBot.create(:show)
    show2 = FactoryBot.create(:show)

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show2, position: "Actor")

    assert_equal 0, user1.overlapping_team_memberships_with(user2)
  end

  test "merge_stats_as_source returns correct statistics" do
    target = FactoryBot.create(:user)
    source = FactoryBot.create(:user)
    source.add_role(:member)

    show = FactoryBot.create(:show)
    TeamMember.create!(user: source, teamwork: show, position: "Actor")

    stats = source.merge_stats_as_source(target)

    assert_equal 1, stats[:team_memberships][:total]
    assert_equal 0, stats[:team_memberships][:overlapping]
    assert_includes stats[:roles].map(&:downcase), "member"
  end

  test "merge_stats_as_source shows overlapping team memberships" do
    target = FactoryBot.create(:user)
    source = FactoryBot.create(:user)

    show = FactoryBot.create(:show)
    TeamMember.create!(user: target, teamwork: show, position: "Director")
    TeamMember.create!(user: source, teamwork: show, position: "Actor")

    stats = source.merge_stats_as_source(target)

    assert_equal 1, stats[:team_memberships][:total]
    assert_equal 1, stats[:team_memberships][:overlapping]
  end
end
