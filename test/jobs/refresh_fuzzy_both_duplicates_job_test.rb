require "test_helper"

class RefreshFuzzyBothDuplicatesJobTest < ActiveJob::TestCase
  test "creates cached duplicates for fuzzy both names with overlapping years" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    RefreshFuzzyBothDuplicatesJob.perform_now

    assert_cached_pair("overlapping", user1, user2)
  end

  test "creates cached duplicates for fuzzy both names with actual overlapping events" do
    user1 = FactoryBot.create(:user, first_name: "Leo", last_name: "Johnson")
    user2 = FactoryBot.create(:user, first_name: "Leon", last_name: "Jonson")

    place_users_on_overlapping_shows(user1, user2)

    RefreshFuzzyBothDuplicatesJob.perform_now

    assert_cached_pair("overlapping", user1, user2)
  end

  test "creates cached duplicates for fuzzy both names without overlapping years" do
    user1 = FactoryBot.create(:user, first_name: "Kate", last_name: "Turnbull")
    user2 = FactoryBot.create(:user, first_name: "Katie", last_name: "Trunbull")

    place_users_on_non_overlapping_shows(user1, user2)

    RefreshFuzzyBothDuplicatesJob.perform_now

    assert_cached_pair("no_overlap", user1, user2)
  end

  test "does not create cached duplicates for exact last name matches" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "TestMutex")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "TestMutex")

    RefreshFuzzyBothDuplicatesJob.perform_now

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

  test "clears old cached results before running" do
    user1 = FactoryBot.create(:user, first_name: "Alice", last_name: "Anderson")
    user2 = FactoryBot.create(:user, first_name: "Bob", last_name: "Brown")
    CachedDuplicate.create!(user1_id: user1.id, user2_id: user2.id, bucket_type: "overlapping")

    assert_equal 1, CachedDuplicate.count

    RefreshFuzzyBothDuplicatesJob.perform_now

    assert_equal 0, CachedDuplicate.count, "Should clear old cached results"
  end

  test "handles multiple users with nil last names in same group" do
    # Both users have nil last names, will be grouped together in "Z" bucket
    user1 = FactoryBot.create(:user, first_name: "Alice", last_name: nil)
    user2 = FactoryBot.create(:user, first_name: "Bob", last_name: nil)

    assert_nothing_raised do
      RefreshFuzzyBothDuplicatesJob.perform_now
    end

    # Should not find any duplicates (nil last names are skipped by fuzzy_last_name_match?)
    assert_equal 0, CachedDuplicate.count
  end

  private

  # The job stores each pair as (lower id, higher id).
  def assert_cached_pair(bucket_type, user1, user2)
    assert_equal [ [ user1.id, user2.id ].sort ], CachedDuplicate.where(bucket_type: bucket_type).pluck(:user1_id, :user2_id)
  end
end
