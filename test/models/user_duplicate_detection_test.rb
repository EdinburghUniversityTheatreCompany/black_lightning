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
end
