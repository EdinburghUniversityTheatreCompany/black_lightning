require "test_helper"

class RefreshFuzzyBothDuplicatesJobTest < ActiveJob::TestCase
  test "creates cached duplicates for fuzzy both names with overlapping years" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    # Both users have no events, so years_overlap? returns true
    RefreshFuzzyBothDuplicatesJob.perform_now

    cached = CachedDuplicate.where(bucket_type: "overlapping")
    assert_equal 1, cached.count
    assert_includes [ cached.first.user1_id, cached.first.user2_id ], user1.id
    assert_includes [ cached.first.user1_id, cached.first.user2_id ], user2.id
  end

  test "creates cached duplicates for fuzzy both names with actual overlapping events" do
    user1 = FactoryBot.create(:user, first_name: "Leo", last_name: "Johnson")
    user2 = FactoryBot.create(:user, first_name: "Leon", last_name: "Jonson")

    show1 = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))
    show2 = FactoryBot.create(:show, start_date: Date.new(2023, 11, 1), end_date: Date.new(2023, 11, 5))

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show2, position: "Actor")

    RefreshFuzzyBothDuplicatesJob.perform_now

    cached = CachedDuplicate.where(bucket_type: "overlapping")
    assert_equal 1, cached.count
    assert_includes [ cached.first.user1_id, cached.first.user2_id ], user1.id
    assert_includes [ cached.first.user1_id, cached.first.user2_id ], user2.id
  end

  test "creates cached duplicates for fuzzy both names without overlapping years" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    show1 = FactoryBot.create(:show, start_date: Date.new(2015, 10, 1), end_date: Date.new(2015, 10, 5))
    show2 = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))

    TeamMember.create!(user: user1, teamwork: show1, position: "Actor")
    TeamMember.create!(user: user2, teamwork: show2, position: "Actor")

    RefreshFuzzyBothDuplicatesJob.perform_now

    cached = CachedDuplicate.where(bucket_type: "no_overlap")
    assert_equal 1, cached.count
    assert_includes [ cached.first.user1_id, cached.first.user2_id ], user1.id
    assert_includes [ cached.first.user1_id, cached.first.user2_id ], user2.id
  end

  test "does not create cached duplicates for exact last name matches" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "TestMutex")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "TestMutex")

    RefreshFuzzyBothDuplicatesJob.perform_now

    # Should not appear in fuzzy_both buckets (these go in buckets 2/3 instead)
    cached = CachedDuplicate.all
    assert_empty cached, "Exact last name matches should not be in cached duplicates"
  end

  test "excludes marked not-duplicates from cached results" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    user1.mark_not_duplicate(user2)

    RefreshFuzzyBothDuplicatesJob.perform_now

    cached = CachedDuplicate.all
    assert_empty cached, "Marked not-duplicates should not appear in cached results"
  end

  test "groups users by first letter of last name" do
    # Create users with similar names but different first letters
    smith1 = FactoryBot.create(:user, first_name: "John", last_name: "Smith")
    smyth = FactoryBot.create(:user, first_name: "Jon", last_name: "Smyth")
    turnbull = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    trunbull = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    RefreshFuzzyBothDuplicatesJob.perform_now

    cached = CachedDuplicate.all
    # Should find Smith/Smyth (both S) and Turnbull/Trunbull (both T)
    assert_equal 2, cached.count, "Should find duplicates within same first letter groups"
  end

  test "clears old cached results before running" do
    # Create a cached entry for users that are NOT actually duplicates
    user1 = FactoryBot.create(:user, first_name: "Alice", last_name: "Anderson")
    user2 = FactoryBot.create(:user, first_name: "Bob", last_name: "Brown")
    CachedDuplicate.create!(user1_id: user1.id, user2_id: user2.id, bucket_type: "overlapping")

    assert_equal 1, CachedDuplicate.count

    # Run job - should clear old entry since these aren't actual duplicates
    RefreshFuzzyBothDuplicatesJob.perform_now

    # Old entry should be cleared
    assert_equal 0, CachedDuplicate.count, "Should clear old cached results"
  end

  test "handles users with nil last names without crashing" do
    user1 = FactoryBot.create(:user, first_name: "Test", last_name: nil)
    user2 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")

    # Should not crash
    assert_nothing_raised do
      RefreshFuzzyBothDuplicatesJob.perform_now
    end

    # Should not find any duplicates (nil last names are skipped)
    assert_equal 0, CachedDuplicate.count
  end

  test "handles multiple users with nil last names in same group" do
    # Both users have nil last names, will be grouped together in "Z" bucket
    user1 = FactoryBot.create(:user, first_name: "Alice", last_name: nil)
    user2 = FactoryBot.create(:user, first_name: "Bob", last_name: nil)

    # Should not crash when checking combinations within the group
    assert_nothing_raised do
      RefreshFuzzyBothDuplicatesJob.perform_now
    end

    # Should not find any duplicates (nil last names are skipped by fuzzy_last_name_match?)
    assert_equal 0, CachedDuplicate.count
  end
end
