# Shared helpers for tests that need to place users on shows spanning specific
# date ranges (duplicate-detection and the fuzzy-duplicates background job).
module TeamMembershipTestHelpers
  # Create a show running over [start_date, end_date] and add `user` to it as an Actor.
  def place_user_on_show(user, start_date:, end_date:)
    show = FactoryBot.create(:show, start_date: start_date, end_date: end_date)
    TeamMember.create!(user: user, teamwork: show, position: "Actor")
    show
  end

  # Place user1 and user2 each on their own show within the 2023/24 academic year,
  # giving them overlapping years of activity.
  def place_users_on_overlapping_shows(user1, user2)
    place_user_on_show(user1, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))
    place_user_on_show(user2, start_date: Date.new(2023, 11, 1), end_date: Date.new(2023, 11, 5))
  end

  # Place user1 (2015) and user2 (2023) on shows far enough apart that their
  # years of activity do not overlap under the default threshold.
  def place_users_on_non_overlapping_shows(user1, user2)
    place_user_on_show(user1, start_date: Date.new(2015, 10, 1), end_date: Date.new(2015, 10, 5))
    place_user_on_show(user2, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))
  end
end
